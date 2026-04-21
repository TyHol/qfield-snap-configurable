# Snap! QField Plugin (Configurable)

The Snap! QField Plugin is a one-click solution for adding features with pictures directly from your device's camera using QField.
This fork extends the [original plugin by opengisch](https://github.com/opengisch/qfield-snap) with a setup dialogue that lets you configure which layer and field photos are saved to — without needing to edit any code.

![Teaser](teaser.gif)

## Features

- **One-click feature addition:** Add a new point feature with a single tap.
- **Camera integration:** Automatically opens the camera; the photo is attached to the new feature.
- **Configurable target layer:** Pin the plugin to a specific point layer rather than always following the active layer.
- **Configurable target field:** Choose exactly which field the photo path is written to.
- **Persistent settings:** Your layer and field choices are remembered between sessions.
- **Smart fallback:** If no layer/field is explicitly configured, the plugin falls back to the active layer and searches for a field named `photo`, `picture`, `image`, `media`, or `camera`.

## Setup Dialogue

The setup dialogue lets you choose the target layer and field.

<img width="308" height="578" alt="Snap-config" src="https://github.com/user-attachments/assets/c4aa50fd-0736-494d-93ef-039b28007956" />


It opens automatically in three situations:

1. **Long-press** the Snap! toolbar button at any time.
2. The active layer is **not a point layer**.
3. No field matching the candidate names (`photo`, `picture`, `image`, `media`, `camera`) is found and no field has been explicitly configured.

### Layer dropdown

Lists all editable point layers in the project. Select **Active Layer** to follow whichever layer is active at the time of capture (the original behaviour).

### Field dropdown

Lists all fields in the selected layer. Select the field you want the photo path written into. The dropdown pre-selects your previously saved choice, or the first candidate-name match if no choice has been saved yet.

> **Note:** The photo path is a relative text string — choose a text/string field.

## Installation

1. **Download QField:**
   - Install [QField on your device](https://qfield.org/get).

2. **Install the plugin:**
   - See [QField plugin documentation](https://docs.qfield.org/how-to/plugins/) for how to sideload a plugin from a local folder or URL.

## Usage

1. **Activate the plugin** in QField's plugin manager.

2. **Configure the target layer and field** (optional):
   - Long-press the Snap! button to open the setup dialogue.
   - Select your target layer and field, then tap **Save**.

3. **Capture a photo:**
   - Tap the Snap! button.
   - The camera opens automatically. Take the photo.
   - The new feature form opens with the photo path pre-filled and your current GPS position set as the geometry.

## Advanced: code-level defaults

For deployments where the layer and field should be fixed in the plugin file itself, edit the two properties near the top of `main.qml`:

```qml
// Candidate field names searched when no field is explicitly configured
property var candidates: ["photo", "picture", "image", "media", "camera"]

// Set to a layer name to pin the plugin to that layer by default
// (overridden by the setup dialogue at runtime; "" means use the active layer)
property var targetLayer: ""
```

## Credits

Based on the original [Snap! plugin](https://github.com/opengisch/qfield-snap) by [opengisch](https://github.com/opengisch).
For a detailed explanation of the original plugin, see their [blog post](https://www.opengis.ch/fr/2024/06/18/supercharge-your-fieldwork-with-qfields-project-and-app-wide-plugins/).

## Contributing

Issues and pull requests welcome on the [GitHub repository](https://github.com/TyHol/qfield-snap-configurable).
