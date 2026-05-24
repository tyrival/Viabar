# Project Theme Color Picker Design

## Goal

Update the project creation and editing color selector so it presents the requested
theme palette in the requested order and supports choosing any custom color through
the macOS system color picker.

## Preset Palette

Replace the existing project theme presets with these nine hex colors, preserving
this display order:

1. `#00CBCF` - blue
2. `#00AB74` - green
3. `#009AFF` - blue
4. `#FFCB24` - yellow
5. `#00CD69` - green
6. `#FF4846` - red
7. `#FFBF00` - orange
8. `#FF6299` - pink
9. `#642FFF` - purple

## Interaction

Keep the existing row of circular preset buttons in `NewProjectView`. Append a
custom-color control after the final preset circle. The custom control opens the
native SwiftUI/macOS color picker and immediately updates the selected project
theme color when the user chooses a color.

The custom control should remain visually compatible with the circular preset
controls: it displays the current custom color when one is selected and exposes a
selected indicator consistent with the preset circles.

## State And Persistence

Continue storing the selected theme color in the existing `selectedColorHex` state
and `Project.accentColor` string property. Convert colors chosen through the system
picker to a normalized `#RRGGBB` string before saving.

Selection display follows these rules:

- If `selectedColorHex` matches a preset, show selection on that preset only.
- If `selectedColorHex` does not match a preset, show selection on the custom color
  control and render it using the saved value.
- Editing an existing project uses the same rules, so previously saved custom
  colors are shown correctly.

No model migration or persistence-layer changes are required.

## Implementation Scope

Change the shared project palette definition in `ViabarColor` and update the
color-row UI plus color-to-hex conversion support used by `NewProjectView`.
Creating and editing projects already share this view, so both flows receive the
new behavior.

## Verification

Perform static review and `git diff --check` only. Do not compile or run the app
unless explicitly requested.
