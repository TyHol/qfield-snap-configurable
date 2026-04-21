import QtQuick
import QtQuick.Controls
import QtCore

import org.qfield
import org.qgis
import Theme

import "qrc:/qml" as QFieldItems

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var positionSource: iface.findItemByObjectName('positionSource')
  property var dashBoard: iface.findItemByObjectName('dashBoard')
  property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')

  // Candidate field names searched as a fallback when no field is explicitly configured
  property var candidates: ["photo", "picture", "image", "media", "camera"]

  // Code-level default target layer name. Set this to a layer name string to pin the
  // plugin to a specific layer without going through the setup dialogue.
  // Empty string means "use the active layer". The setup dialogue overrides this at runtime.
  property var targetLayer: ""

  // Persisted settings — empty string means "use active layer / search candidate names"
  Settings {
    id: appSettings
    category: "qfield-snap"
    property string pointLayerName: ""
    property string fieldName: ""
  }

  // Models backing the two dropdowns in the setup dialogue
  ListModel { id: layerPickerModel }
  ListModel { id: fieldPickerModel }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(snapButton)
  }

  // Returns the layer to snap into, in priority order:
  //   1. User-configured layer (saved in appSettings via setup dialogue)
  //   2. Code-level default (targetLayer property above)
  //   3. Whatever is currently active in the dashboard
  function resolveLayer() {
    var saved = appSettings.pointLayerName
    if (saved && saved !== "") {
      var found = qgisProject.mapLayersByName(saved)
      if (found && found.length > 0) return found[0]
      // Saved layer has disappeared from the project — clear the stale setting
      appSettings.pointLayerName = ""
    }
    // Fall back to the code-level default if one is set
    if (targetLayer && targetLayer !== "") {
      var byDefault = qgisProject.mapLayersByName(targetLayer)
      if (byDefault && byDefault.length > 0) return byDefault[0]
    }
    return dashBoard.activeLayer
  }

  // Returns the field name to write the photo path into.
  // The explicitly configured field takes priority; the candidates list is the fallback.
  function resolveField(layer) {
    if (!layer) return null
    var names = layer.fields.names
    var configured = appSettings.fieldName
    if (configured && configured !== "" && names.indexOf(configured) >= 0)
      return configured
    // Fallback: try each candidate name in order
    for (var i = 0; i < candidates.length; i++) {
      if (names.indexOf(candidates[i]) >= 0) return candidates[i]
    }
    return null
  }

  // Fills the layer dropdown with all point-geometry vector layers in the project.
  // "Active Layer" is always index 0 so the original behaviour is preserved by default.
  // Layers whose names begin with "_" are grouped into a "Private Layers" section,
  // mirroring the convention used in the Conversion_tools plugin.
  function populateLayerModel() {
    layerPickerModel.clear()

    var normal = [], priv = []
    try {
      // ProjectUtils.mapLayers() is the correct QField API for iterating project layers
      var all = ProjectUtils.mapLayers(qgisProject)
      for (var id in all) {
        var lyr = all[id]
        try {
          if (lyr &&
              lyr.geometryType &&
              lyr.geometryType() === Qgis.GeometryType.Point &&
              lyr.supportsEditing === true) {
            // Private flag value 8 matches the convention used in Conversion_tools
            var isPrivate = false
            try { isPrivate = (lyr.flags & 8) !== 0 } catch (e2) {}
            if (isPrivate) priv.push(lyr)
            else normal.push(lyr)
          }
        } catch (e) {}
      }
    } catch (e) {}

    normal.sort(function(a, b) { return a.name.localeCompare(b.name) })
    priv.sort(function(a, b) { return a.name.localeCompare(b.name) })

    if (normal.length === 0 && priv.length === 0) {
      layerPickerModel.append({ "name": qsTr("— no editable point layers —"), "isHeader": true })
      layerDropdown.currentIndex = 0
      return
    }

    // "Active Layer" is always index 0 — preserves original behaviour when nothing is configured
    layerPickerModel.append({ "name": qsTr("Active Layer"), "isHeader": false })

    for (var i = 0; i < normal.length; i++)
      layerPickerModel.append({ "name": normal[i].name, "isHeader": false })

    if (priv.length > 0) {
      layerPickerModel.append({ "name": qsTr("— Private Layers —"), "isHeader": true })
      for (var j = 0; j < priv.length; j++)
        layerPickerModel.append({ "name": priv[j].name, "isHeader": false })
    }

    // Restore the previously saved layer selection
    var saved = appSettings.pointLayerName
    for (var k = 1; k < layerPickerModel.count; k++) {
      var item = layerPickerModel.get(k)
      if (!item.isHeader && item.name === saved) {
        layerDropdown.currentIndex = k
        return
      }
    }
    layerDropdown.currentIndex = 0
  }

  // Fills the field dropdown with all fields from the named layer.
  // QgsField type properties are not accessible from QField's QML bindings, so all
  // fields are listed — the dropdown pre-selects the saved field, or the first
  // candidate-name match, so the correct choice is obvious without type filtering.
  function populateFieldModel(layerName) {
    fieldPickerModel.clear()

    var lyr = null
    if (!layerName || layerName === qsTr("Active Layer")) {
      lyr = dashBoard.activeLayer
    } else {
      var found = qgisProject.mapLayersByName(layerName)
      if (found && found.length > 0) lyr = found[0]
    }

    if (!lyr) {
      fieldPickerModel.append({ "name": qsTr("— no layer selected —"), "isHeader": true })
      fieldDropdown.currentIndex = 0
      return
    }

    var fieldNames = lyr.fields.names

    if (fieldNames.length === 0) {
      fieldPickerModel.append({ "name": qsTr("— no fields available —"), "isHeader": true })
      fieldDropdown.currentIndex = 0
      return
    }

    for (var i = 0; i < fieldNames.length; i++)
      fieldPickerModel.append({ "name": fieldNames[i], "isHeader": false })

    // Prefer the saved field; fall back to the first candidate-name match
    var saved = appSettings.fieldName
    for (var k = 0; k < fieldPickerModel.count; k++) {
      if (fieldPickerModel.get(k).name === saved) {
        fieldDropdown.currentIndex = k
        return
      }
    }
    for (var c = 0; c < candidates.length; c++) {
      for (var m = 0; m < fieldPickerModel.count; m++) {
        if (fieldPickerModel.get(m).name === candidates[c]) {
          fieldDropdown.currentIndex = m
          return
        }
      }
    }
    fieldDropdown.currentIndex = 0
  }

  // Prepares and opens the setup dialogue
  function openSetupDialogue() {
    populateLayerModel()
    var idx = layerDropdown.currentIndex
    var layerName = (idx === 0) ? "" : layerPickerModel.get(idx).name
    populateFieldModel(layerName)
    setupDialogue.open()
  }

  Loader {
    id: cameraLoader
    active: false
    sourceComponent: Component {
      QFieldItems.QFieldCamera {
        visible: false
        Component.onCompleted: { open() }
        onFinished: (path) => { close(); snap(path) }
        onCanceled: { close() }
        onClosed: { cameraLoader.active = false }
      }
    }
  }

  QfToolButton {
    id: snapButton
    bgcolor: Theme.darkGray
    iconSource: Theme.getThemeVectorIcon('ic_camera_photo_black_24dp')
    iconColor: Theme.mainColor
    round: true

    onClicked: {
      if (!positionSource.active ||
          !positionSource.positionInformation.latitudeValid ||
          !positionSource.positionInformation.longitudeValid) {
        mainWindow.displayToast(qsTr('Snap requires positioning to be active and returning a valid position'))
        return
      }

      var layer = resolveLayer()

      // Not a point layer — explain why and open setup so the user can correct it
      if (!layer || layer.geometryType() !== Qgis.GeometryType.Point) {
        mainWindow.displayToast(qsTr('Active layer is not a point layer — opening setup'))
        openSetupDialogue()
        return
      }

      // No matching field found — explain why and open setup
      if (!resolveField(layer)) {
        mainWindow.displayToast(qsTr('No suitable photo field found — opening setup'))
        openSetupDialogue()
        return
      }

      platformUtilities.createDir(qgisProject.homePath, 'DCIM')
      cameraLoader.active = true
    }

    // Long press on the toolbar icon opens setup at any time
    onPressAndHold: {
      openSetupDialogue()
    }
  }

  // Setup dialogue: choose the target layer and field for photo capture
  Dialog {
    id: setupDialogue
    parent: mainWindow.contentItem
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 400)
    title: qsTr("Snap Photo Setup")
    modal: true
    standardButtons: Dialog.Save | Dialog.Cancel

    Column {
      width: parent.width
      spacing: 10

      Label { text: qsTr("Target layer:"); font.pixelSize: 12; font.bold: true }

      ComboBox {
        id: layerDropdown
        width: parent.width
        model: layerPickerModel
        textRole: "name"
        onActivated: {
          var item = layerPickerModel.get(currentIndex)
          // Skip non-selectable header rows
          if (item.isHeader) { currentIndex = Math.max(0, currentIndex - 1); return }
          // Repopulate the field list whenever the layer selection changes
          populateFieldModel(currentIndex === 0 ? "" : item.name)
        }
        delegate: ItemDelegate {
          width: layerDropdown.width
          enabled: !model.isHeader
          contentItem: Text {
            text: model.name
            font.italic: model.isHeader
            color: model.isHeader ? "#888888" : (highlighted ? "#ffffff" : "#000000")
            verticalAlignment: Text.AlignVCenter
            leftPadding: model.isHeader ? 4 : 12
          }
          highlighted: layerDropdown.highlightedIndex === index
        }
      }

      Label { text: qsTr("Photo field (must be a text/string field):"); font.pixelSize: 12; font.bold: true }

      ComboBox {
        id: fieldDropdown
        width: parent.width
        model: fieldPickerModel
        textRole: "name"
        onActivated: {
          var item = fieldPickerModel.get(currentIndex)
          if (item.isHeader) { currentIndex = 0 }
        }
        delegate: ItemDelegate {
          width: fieldDropdown.width
          enabled: !model.isHeader
          contentItem: Text {
            text: model.name
            font.italic: model.isHeader
            color: model.isHeader ? "#888888" : (highlighted ? "#ffffff" : "#000000")
            verticalAlignment: Text.AlignVCenter
            leftPadding: model.isHeader ? 4 : 12
          }
          highlighted: fieldDropdown.highlightedIndex === index
        }
      }

      // Hint shown when either dropdown is left at its default, reminding the user
      // that the candidate-name fallback is still active in that case
      Label {
        visible: layerDropdown.currentIndex === 0 || fieldDropdown.currentIndex === 0
        width: parent.width
        text: qsTr("Without an explicit selection the plugin will use the active layer and search for a field named: %1").arg(candidates.join(', '))
        wrapMode: Text.WordWrap
        font.pixelSize: 10
        color: "#666666"
      }
    }

    onAccepted: {
      // Persist layer selection — empty string means "follow the active layer"
      var layerItem = layerPickerModel.get(layerDropdown.currentIndex)
      appSettings.pointLayerName =
        (layerDropdown.currentIndex === 0 || !layerItem || layerItem.isHeader)
          ? "" : layerItem.name

      // Persist field selection — empty string means "search candidate names"
      if (fieldPickerModel.count > 0) {
        var fieldItem = fieldPickerModel.get(fieldDropdown.currentIndex)
        appSettings.fieldName = (!fieldItem || fieldItem.isHeader) ? "" : fieldItem.name
      } else {
        appSettings.fieldName = ""
      }
    }
  }

  function snap(path) {
    let today = new Date()
    let relativePath = 'DCIM/' + today.getFullYear()
                               + (today.getMonth() + 1).toString().padStart(2, 0)
                               + today.getDate().toString().padStart(2, 0)
                               + today.getHours().toString().padStart(2, 0)
                               + today.getMinutes().toString().padStart(2, 0)
                               + today.getSeconds().toString().padStart(2, 0)
                               + '.' + FileUtils.fileSuffix(path)
    platformUtilities.renameFile(path, qgisProject.homePath + '/' + relativePath)

    // Use the resolved layer (configured or active) for geometry and field writing
    var layer = resolveLayer()
    const pos = GeometryUtils.reprojectPoint(
      positionSource.projectedPosition,
      positionSource.coordinateTransformer.destinationCrs,
      layer.crs
    )
    const elevation = positionSource.positionInformation.elevation
    let wkt = ''
    switch (layer.wkbType()) {
      case Qgis.WkbType.MultiPointZ:  wkt = 'MULTIPOINTZ((' + pos.x + ' ' + pos.y + ' ' + elevation + '))'; break
      case Qgis.WkbType.MultiPointM:  wkt = 'MULTIPOINTM((' + pos.x + ' ' + pos.y + ' 0 ))'; break
      case Qgis.WkbType.MultiPointZM: wkt = 'MULTIPOINTZM((' + pos.x + ' ' + pos.y + ' ' + elevation + ' 0))'; break
      case Qgis.WkbType.MultiPoint:   wkt = 'MULTIPOINT((' + pos.x + ' ' + pos.y + '))'; break
      case Qgis.WkbType.PointZ:       wkt = 'POINTZ(' + pos.x + ' ' + pos.y + ' ' + elevation + ')'; break
      case Qgis.WkbType.PointM:       wkt = 'POINTM(' + pos.x + ' ' + pos.y + ' 0 )'; break
      case Qgis.WkbType.PointZM:      wkt = 'POINTZM(' + pos.x + ' ' + pos.y + ' ' + elevation + ' 0)'; break
      case Qgis.WkbType.Point:        wkt = 'POINT(' + pos.x + ' ' + pos.y + ')'; break
    }

    let geometry = GeometryUtils.createGeometryFromWkt(wkt)
    let feature = FeatureUtils.createBlankFeature(layer.fields, geometry)

    // Configured field takes priority; candidate names are the fallback
    var fieldName = resolveField(layer)
    if (fieldName) {
      let fieldNames = feature.fields.names
      feature.setAttribute(fieldNames.indexOf(fieldName), relativePath)
    }

    // currentLayer must be set explicitly so the form saves to the configured
    // layer rather than defaulting to whatever is active in the dashboard
    overlayFeatureFormDrawer.featureModel.currentLayer = layer
    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.featureModel.resetAttributes(true)
    overlayFeatureFormDrawer.state = 'Add'
    overlayFeatureFormDrawer.open()
  }
}
