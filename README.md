# Snap! QField Plugin (Multi-Mode)

A multi-mode capture plugin for QField — photo, video, audio, sketch, and
voice/text notes, all from one toolbar button. Configurable target layer,
media field, notes field, and default tap action.

Install: <img width="80" height="80" alt="image" src="https://github.com/user-attachments/assets/bf9d3264-5a2d-41c9-9c01-b3811e9c1d0d" />

This fork extends the [original plugin by opengisch](https://github.com/opengisch/qfield-snap)
with multiple capture modes and a setup dialogue.

![Teaser](teaser.gif)

## Features

- **Multi-mode capture:** Camera (photo & video), audio recording, sketch
  drawing, and voice/text notes — all from one button.
- **One-tap or chooser:** Set a default mode for single-tap capture, or
  choose "Ask each time" to see a mode picker dialog.
- **Camera with video toggle:** Photo and video capture in one interface
  (`allowCaptureModeToggle`).
- **Audio recording:** Records audio clips via QField's built-in audio
  recorder.
- **Sketch:** Opens QField's built-in sketcher for freehand drawings.
- **Voice / Text Note:** Dictate via your keyboard's microphone button, or
  type directly. The text is written into a configurable notes field.
- **Configurable target layer:** Pin the plugin to a specific point layer
  rather than always following the active layer.
- **Configurable media field:** Choose exactly which field the photo/video/
  audio/sketch path is written to.
- **Configurable notes field:** Choose which text field receives dictated or
  typed notes.
- **Persistent settings:** All choices are remembered between sessions.
- **Smart fallback:** If no layer/field is explicitly configured, the plugin
  falls back to the active layer and searches for candidate field names.

## Setup Dialogue

Long-press the toolbar button at any time to open the setup dialogue.

It also opens automatically when:
- The active layer is **not a point layer**.
- No field matching the candidate names is found and no field has been
  explicitly configured.

### Layer dropdown

Lists all editable point layers in the project. Select **Active Layer** to
follow whichever layer is active at the time of capture (the original
behaviour).

### Media field dropdown

Lists all fields in the selected layer. Select the field you want the
photo/video/audio/sketch path written into.

> **Note:** The media path is a relative text string — choose a text/string
> field.

### Notes field dropdown

Lists all fields in the selected layer, plus "— none —". Select the text
field you want voice/text notes written into. If left as "— none —", the
plugin searches for a field named `note`, `notes`, `description`, `comment`,
or `comments`. If none of these exist, the Voice / Text Note action is
disabled.

### Tap action dropdown

Choose the default capture mode:
- **Ask each time** — tapping the toolbar button opens a dialog with all
  four modes.
- **Camera (Photo / Video)** — opens the camera directly (default).
- **Audio Recording** — starts the audio recorder directly.
- **Sketch** — opens the sketcher directly.
- **Voice / Text Note** — opens the note dialog directly.

Long-press always opens the setup dialogue regardless of this setting.

## Installation

1. **Download QField:**
   - Install [QField on your device](https://qfield.org/get).

2. **Install the plugin:**
   - See [QField plugin documentation](https://docs.qfield.org/how-to/plugins/)
     for how to sideload a plugin from a local folder or URL.

## Usage

1. **Activate the plugin** in QField's plugin manager.

2. **Configure** (optional):
   - Long-press the toolbar button to open the setup dialogue.
   - Select your target layer, media field, notes field, and default tap
     action, then tap **Save**.

3. **Capture:**
   - **Tap** the toolbar button to run the default mode (or open the mode
     chooser if set to "Ask each time").
   - The chosen capture tool opens. Complete the capture.
   - The new feature form opens with the media path or note text pre-filled
     and your current GPS position set as the geometry.

## Technical notes

- **Camera/Audio** use QField's `QFieldCamera` and `QFieldAudioRecorder`
  components via `Loader` (instantiated on demand, destroyed on close).
- **Sketch** uses the app-level `QFieldSketcher` singleton accessed via
  `iface.findItemByObjectName('sketcher')` — it cannot be instantiated
  standalone from a plugin.
- **Mode chooser** uses a plain `Dialog` with `Button` items. The original
  `QfToolButtonPie` (pie menu) is not reliably accessible from plugins.
- **Icons** use `Theme.getThemeVectorIcon()` for cross-platform rendering.

## Advanced: code-level defaults

For deployments where the layer and field should be fixed in the plugin file
itself, edit the properties near the top of `main.qml`:

```qml
// Candidate field names for media (photo/video/audio/sketch path)
property var candidates: ["photo", "picture", "image", "media", "camera"]

// Candidate field names for text notes
property var noteCandidates: ["note", "notes", "description", "comment", "comments"]

// Set to a layer name to pin the plugin to that layer by default
// (overridden by the setup dialogue at runtime; "" means use the active layer)
property var targetLayer: ""
```

## Credits

Based on the original [Snap! plugin](https://github.com/opengisch/qfield-snap)
by [opengisch](https://github.com/opengisch). For a detailed explanation of
the original plugin, see their
[blog post](https://www.opengis.ch/fr/2024/06/18/supercharge-your-fieldwork-with-qfields-project-and-app-wide-plugins/).

## Contributing

Issues and pull requests welcome on the
[GitHub repository](https://github.com/TyHol/qfield-snap-configurable).
