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

    // Candidate field names searched as a fallback when no media field is explicitly configured
    property var candidates: ["photo", "picture", "image", "media", "camera"]

    // Candidate field names searched as a fallback when no notes field is explicitly configured
    property var noteCandidates: ["note", "notes", "description", "comment", "comments"]

    // Options for the "default action" dropdown in the setup dialogue.
    // "ask" means: tapping the toolbar button opens the pie menu of all modes.
    property var defaultModeOptions: [
        { value: "ask", label: qsTr("Ask each time (pie menu)") },
        { value: "camera", label: qsTr("Camera (Photo / Video)") },
        { value: "audio", label: qsTr("Audio Recording") },
        { value: "sketch", label: qsTr("Sketch") },
        { value: "note", label: qsTr("Voice / Text Note") }
    ]

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
        property string noteFieldName: ""
        property string defaultMode: "ask"
    }

    // Models backing the dropdowns in the setup dialogue
    ListModel { id: layerPickerModel }
    ListModel { id: fieldPickerModel }
    ListModel { id: noteFieldPickerModel }
    ListModel { id: defaultModePickerModel }

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(snapButton)

        // The default-action options are static, so this model is built once
        for (var i = 0; i < defaultModeOptions.length; i++)
            defaultModePickerModel.append({ "value": defaultModeOptions[i].value, "label": defaultModeOptions[i].label })
    }

    // Returns the layer to capture into, in priority order:
    // 1. User-configured layer (saved in appSettings via setup dialogue)
    // 2. Code-level default (targetLayer property above)
    // 3. Whatever is currently active in the dashboard
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

    // Returns the field name to write the media (photo/video/audio/sketch) path into.
    // The explicitly configured field takes priority; the candidates list is the fallback.
    function resolveMediaField(layer) {
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

    // Returns the field name to write a dictated/typed note into.
    // Returns null if no notes field is configured and none of the candidate names exist —
    // in that case the Voice / Text Note action is disabled rather than guessed at.
    function resolveNoteField(layer) {
        if (!layer) return null
        var names = layer.fields.names
        var configured = appSettings.noteFieldName
        if (configured && configured !== "" && names.indexOf(configured) >= 0)
            return configured

        for (var i = 0; i < noteCandidates.length; i++) {
            if (names.indexOf(noteCandidates[i]) >= 0) return noteCandidates[i]
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

    // Resolves the QgsVectorLayer for a layer name as used by the setup dialogue dropdowns
    // (handles the special "Active Layer" entry and empty/blank selections).
    function layerFromPickerName(layerName) {
        if (!layerName || layerName === qsTr("Active Layer")) {
            return dashBoard.activeLayer
        }
        var found = qgisProject.mapLayersByName(layerName)
        if (found && found.length > 0) return found[0]
        return null
    }

    // Fills the media field dropdown with all fields from the named layer.
    // QgsField type properties are not accessible from QField's QML bindings, so all
    // fields are listed — the dropdown pre-selects the saved field, or the first
    // candidate-name match, so the correct choice is obvious without type filtering.
    function populateFieldModel(layerName) {
        fieldPickerModel.clear()
        var lyr = layerFromPickerName(layerName)

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

    // Fills the notes field dropdown with all fields from the named layer, plus a
    // "— none —" option at index 0. Unlike the media field, the notes field is optional:
    // if left as "— none —" (and no candidate-name match exists), the Voice / Text Note
    // action is disabled.
    function populateNoteFieldModel(layerName) {
        noteFieldPickerModel.clear()
        noteFieldPickerModel.append({ "name": qsTr("— none —"), "isHeader": false })

        var lyr = layerFromPickerName(layerName)
        if (!lyr) {
            noteFieldDropdown.currentIndex = 0
            return
        }

        var fieldNames = lyr.fields.names
        for (var i = 0; i < fieldNames.length; i++)
            noteFieldPickerModel.append({ "name": fieldNames[i], "isHeader": false })

        // Prefer the saved field; fall back to the first candidate-name match
        var saved = appSettings.noteFieldName
        for (var k = 0; k < noteFieldPickerModel.count; k++) {
            if (noteFieldPickerModel.get(k).name === saved) {
                noteFieldDropdown.currentIndex = k
                return
            }
        }

        for (var c = 0; c < noteCandidates.length; c++) {
            for (var m = 0; m < noteFieldPickerModel.count; m++) {
                if (noteFieldPickerModel.get(m).name === noteCandidates[c]) {
                    noteFieldDropdown.currentIndex = m
                    return
                }
            }
        }

        noteFieldDropdown.currentIndex = 0
    }

    // Prepares and opens the setup dialogue
    function openSetupDialogue() {
        populateLayerModel()
        var idx = layerDropdown.currentIndex
        var layerName = (idx === 0) ? "" : layerPickerModel.get(idx).name
        populateFieldModel(layerName)
        populateNoteFieldModel(layerName)

        // Restore the saved default-action selection
        defaultModeDropdown.currentIndex = 0
        for (var i = 0; i < defaultModePickerModel.count; i++) {
            if (defaultModePickerModel.get(i).value === appSettings.defaultMode) {
                defaultModeDropdown.currentIndex = i
                break
            }
        }

        setupDialogue.open()
    }

    // Checks positioning is active before any capture/note action
    function positionAvailable() {
        if (!positionSource.active ||
            !positionSource.positionInformation.latitudeValid ||
            !positionSource.positionInformation.longitudeValid) {
            mainWindow.displayToast(qsTr('This requires positioning to be active and returning a valid position'))
            return false
        }
        return true
    }

    // Builds a WKT point geometry string matching the layer's WKB type
    function buildPointWkt(layer, pos, elevation) {
        switch (layer.wkbType()) {
            case Qgis.WkbType.MultiPointZ: return 'MULTIPOINTZ((' + pos.x + ' ' + pos.y + ' ' + elevation + '))'
            case Qgis.WkbType.MultiPointM: return 'MULTIPOINTM((' + pos.x + ' ' + pos.y + ' 0 ))'
            case Qgis.WkbType.MultiPointZM: return 'MULTIPOINTZM((' + pos.x + ' ' + pos.y + ' ' + elevation + ' 0))'
            case Qgis.WkbType.MultiPoint: return 'MULTIPOINT((' + pos.x + ' ' + pos.y + '))'
            case Qgis.WkbType.PointZ: return 'POINTZ(' + pos.x + ' ' + pos.y + ' ' + elevation + ')'
            case Qgis.WkbType.PointM: return 'POINTM(' + pos.x + ' ' + pos.y + ' 0 )'
            case Qgis.WkbType.PointZM: return 'POINTZM(' + pos.x + ' ' + pos.y + ' ' + elevation + ' 0)'
            case Qgis.WkbType.Point: return 'POINT(' + pos.x + ' ' + pos.y + ')'
        }
        return ''
    }

    // Creates a blank point feature at the current GPS position on the given layer
    function createFeatureAtPosition(layer) {
        const pos = GeometryUtils.reprojectPoint(
            positionSource.projectedPosition,
            positionSource.coordinateTransformer.destinationCrs,
            layer.crs
        )
        const elevation = positionSource.positionInformation.elevation
        let wkt = buildPointWkt(layer, pos, elevation)
        let geometry = GeometryUtils.createGeometryFromWkt(wkt)
        return FeatureUtils.createBlankFeature(layer.fields, geometry)
    }

    // Opens the overlay feature form for the given feature on the given layer
    function openFeatureForm(layer, feature) {
        // currentLayer must be set explicitly so the form saves to the configured
        // layer rather than defaulting to whatever is active in the dashboard
        overlayFeatureFormDrawer.featureModel.currentLayer = layer
        overlayFeatureFormDrawer.featureModel.feature = feature
        overlayFeatureFormDrawer.featureModel.resetAttributes(true)
        overlayFeatureFormDrawer.state = 'Add'
        overlayFeatureFormDrawer.open()
    }

    // --- Capture loaders -----------------------------------------------------------
    // Each loader hosts one of QField's built-in capture popups. They all follow the
    // same finished(path) / canceled signal pattern, so they share the snap(path)
    // handler below.

    Loader {
        id: cameraLoader
        active: false
        sourceComponent: Component {
            QFieldItems.QFieldCamera {
                visible: false
                allowCaptureModeToggle: true // lets the user toggle between photo and video
                Component.onCompleted: { open() }
                onFinished: (path) => { close(); snap(path) }
                onCanceled: { close() }
                onClosed: { cameraLoader.active = false }
            }
        }
    }

    Loader {
        id: audioLoader
        active: false
        sourceComponent: Component {
            QFieldItems.QFieldAudioRecorder {
                visible: false
                Component.onCompleted: { open() }
                onFinished: (path) => { close(); snap(path) }
                onCanceled: { close() }
                onClosed: { audioLoader.active = false }
            }
        }
    }

    // Use the app-level sketcher singleton instead of creating a new instance
    // (QFieldSketcher is designed to be a single instance managed by the app).
    property var sketcher: iface.findItemByObjectName('sketcher')
    property bool _sketchPending: false

    Connections {
        target: sketcher
        enabled: _sketchPending
        function onFinished(path) { _sketchPending = false; snap(path) }
        function onCancelled() { _sketchPending = false }
    }

    // Starts the requested capture mode, after checking position/layer/field setup
    function startCapture(kind) {
        if (!positionAvailable()) return

        var layer = resolveLayer()

        if (!layer || layer.geometryType() !== Qgis.GeometryType.Point) {
            mainWindow.displayToast(qsTr('Active layer is not a point layer — opening setup'))
            openSetupDialogue()
            return
        }

        if (!resolveMediaField(layer)) {
            mainWindow.displayToast(qsTr('No suitable media field found — opening setup'))
            openSetupDialogue()
            return
        }

        platformUtilities.createDir(qgisProject.homePath, 'DCIM')

        switch (kind) {
            case 'camera': cameraLoader.active = true; break
            case 'audio': audioLoader.active = true; break
            case 'sketch':
                if (sketcher) {
                    _sketchPending = true
                    sketcher.clear()
                    sketcher.open()
                } else {
                    mainWindow.displayToast(qsTr('Sketcher not available'))
                }
                break
        }
    }

    QfToolButton {
        id: snapButton
        bgcolor: Theme.darkGray
        iconSource: Theme.getThemeVectorIcon('ic_camera_photo_black_24dp')
        iconColor: Theme.mainColor
        round: true

        onClicked: {
            if (!positionAvailable()) return

            var layer = resolveLayer()

            // Not a point layer — explain why and open setup so the user can correct it
            if (!layer || layer.geometryType() !== Qgis.GeometryType.Point) {
                mainWindow.displayToast(qsTr('Active layer is not a point layer — opening setup'))
                openSetupDialogue()
                return
            }

            // A default action skips the pie menu and runs that mode directly
            switch (appSettings.defaultMode) {
                case 'camera':
                case 'audio':
                case 'sketch':
                    startCapture(appSettings.defaultMode)
                    break
                case 'note':
                    openNoteDialog()
                    break
                default:
                    openCaptureMenu()
                    break
            }
        }

        // Long press on the toolbar icon opens setup at any time
        onPressAndHold: {
            openSetupDialogue()
        }
    }

    // Opens the capture mode chooser dialog
    function openCaptureMenu() {
        captureMenuDialog.open()
    }

    // Simple dialog for choosing capture mode — replaces QfToolButtonPie which
    // is not reliably accessible from plugins.
    Dialog {
        id: captureMenuDialog
        parent: mainWindow.contentItem
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 300)
        title: qsTr("Capture Mode")
        modal: true

        Column {
            width: parent.width
            spacing: 4

            Button {
                width: parent.width
                text: qsTr("Camera (Photo / Video)")
                icon.source: Theme.getThemeVectorIcon("ic_camera_photo_black_24dp")
                flat: true
                font.pixelSize: 13
                onClicked: { captureMenuDialog.close(); startCapture('camera') }
            }
            Button {
                width: parent.width
                text: qsTr("Audio Recording")
                icon.source: Theme.getThemeVectorIcon("ic_microphone_black_24dp")
                flat: true
                font.pixelSize: 13
                onClicked: { captureMenuDialog.close(); startCapture('audio') }
            }
            Button {
                width: parent.width
                text: qsTr("Sketch")
                icon.source: Theme.getThemeVectorIcon("ic_freehand_white_24dp")
                flat: true
                font.pixelSize: 13
                onClicked: { captureMenuDialog.close(); startCapture('sketch') }
            }
            Button {
                width: parent.width
                text: qsTr("Voice / Text Note")
                icon.source: Theme.getThemeVectorIcon("ic_note_white_24dp")
                flat: true
                font.pixelSize: 13
                enabled: resolveNoteField(resolveLayer()) !== null
                onClicked: { captureMenuDialog.close(); openNoteDialog() }
            }
        }

        footer: Button {
            width: parent.width
            text: qsTr("Cancel")
            flat: true
            font.pixelSize: 12
            onClicked: captureMenuDialog.close()
        }
    }

    // Setup dialogue: choose the target layer, media field, and notes field
    Dialog {
        id: setupDialogue
        parent: mainWindow.contentItem
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 400)
        title: qsTr("Snap Setup")
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
                    // Repopulate the field lists whenever the layer selection changes
                    var layerName = currentIndex === 0 ? "" : item.name
                    populateFieldModel(layerName)
                    populateNoteFieldModel(layerName)
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

            Label { text: qsTr("Media field (photo / video / audio / sketch path):"); font.pixelSize: 12; font.bold: true }
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
                text: qsTr("Without an explicit selection the plugin will use the active layer and search for a media field named: %1").arg(candidates.join(', '))
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                color: "#666666"
            }

            Label { text: qsTr("Notes field (optional, text — for voice/typed notes):"); font.pixelSize: 12; font.bold: true }
            ComboBox {
                id: noteFieldDropdown
                width: parent.width
                model: noteFieldPickerModel
                textRole: "name"
                delegate: ItemDelegate {
                    width: noteFieldDropdown.width
                    contentItem: Text {
                        text: model.name
                        color: highlighted ? "#ffffff" : "#000000"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 12
                    }
                    highlighted: noteFieldDropdown.highlightedIndex === index
                }
            }

            Label {
                visible: noteFieldDropdown.currentIndex === 0
                width: parent.width
                text: qsTr("With no notes field selected, the plugin will search for a field named: %1. If none of these exist, the Voice / Text Note action is disabled.").arg(noteCandidates.join(', '))
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                color: "#666666"
            }

            Label { text: qsTr("Tap action:"); font.pixelSize: 12; font.bold: true }
            ComboBox {
                id: defaultModeDropdown
                width: parent.width
                model: defaultModePickerModel
                textRole: "label"
            }
            Label {
                width: parent.width
                text: qsTr("Choose a single mode to launch directly when the toolbar button is tapped, or \"Ask each time\" to show the pie menu of all modes. Long-press always opens this setup dialogue.")
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

            // Persist media field selection — empty string means "search candidate names"
            if (fieldPickerModel.count > 0) {
                var fieldItem = fieldPickerModel.get(fieldDropdown.currentIndex)
                appSettings.fieldName = (!fieldItem || fieldItem.isHeader) ? "" : fieldItem.name
            } else {
                appSettings.fieldName = ""
            }

            // Persist notes field selection — index 0 ("— none —") means "search candidate names"
            if (noteFieldPickerModel.count > 0 && noteFieldDropdown.currentIndex > 0) {
                var noteItem = noteFieldPickerModel.get(noteFieldDropdown.currentIndex)
                appSettings.noteFieldName = noteItem ? noteItem.name : ""
            } else {
                appSettings.noteFieldName = ""
            }

            // Persist the tap-action selection
            var modeItem = defaultModePickerModel.get(defaultModeDropdown.currentIndex)
            appSettings.defaultMode = modeItem ? modeItem.value : "ask"
        }
    }

    // Voice / Text Note dialogue. There is no QML speech-recognition API in QField —
    // instead this is a plain TextArea, and the user dictates into it using their
    // phone keyboard's microphone/dictation button (Gboard, iOS keyboard, etc.).
    Dialog {
        id: noteDialog
        parent: mainWindow.contentItem
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 400)
        title: qsTr("Voice / Text Note")
        modal: true
        standardButtons: Dialog.Save | Dialog.Cancel

        Column {
            width: parent.width
            spacing: 10

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Tap the field below, then use your keyboard's microphone button to dictate, or type directly.")
                font.pixelSize: 11
                color: "#666666"
            }

            ScrollView {
                width: parent.width
                height: 150

                TextArea {
                    id: noteTextArea
                    wrapMode: TextArea.Wrap
                    placeholderText: qsTr("Tap here and dictate or type your note…")
                }
            }
        }

        onOpened: {
            noteTextArea.text = ""
            noteTextArea.forceActiveFocus()
        }

        onAccepted: {
            addNote(noteTextArea.text)
        }

        onRejected: {
            noteTextArea.text = ""
        }
    }

    // Opens the note dialogue after checking position/layer/field setup
    function openNoteDialog() {
        if (!positionAvailable()) return

        var layer = resolveLayer()

        if (!layer || layer.geometryType() !== Qgis.GeometryType.Point) {
            mainWindow.displayToast(qsTr('Active layer is not a point layer — opening setup'))
            openSetupDialogue()
            return
        }

        if (!resolveNoteField(layer)) {
            mainWindow.displayToast(qsTr('No notes field configured — opening setup'))
            openSetupDialogue()
            return
        }

        noteDialog.open()
    }

    // Creates a feature at the current position with the dictated/typed text written
    // into the configured notes field, then opens the form for review
    function addNote(text) {
        if (!text || text.trim() === "") return

        var layer = resolveLayer()
        var noteField = resolveNoteField(layer)
        if (!layer || !noteField) return

        let feature = createFeatureAtPosition(layer)

        let fieldNames = feature.fields.names
        feature.setAttribute(fieldNames.indexOf(noteField), text.trim())

        openFeatureForm(layer, feature)
    }

    // Handles the result of any media capture (photo, video, audio clip, or sketch).
    // Renames the captured file into DCIM with a timestamped name, writes its relative
    // path into the configured media field, and opens the feature form for review.
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
        let feature = createFeatureAtPosition(layer)

        // Configured field takes priority; candidate names are the fallback
        var fieldName = resolveMediaField(layer)
        if (fieldName) {
            let fieldNames = feature.fields.names
            feature.setAttribute(fieldNames.indexOf(fieldName), relativePath)
        }

        openFeatureForm(layer, feature)
    }
}
