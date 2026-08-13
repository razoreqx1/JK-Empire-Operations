# EOC 2.8 GA — Build 199

## Construction-vessel assignment

- Reassigns an eligible player construction vessel already performing another role.
- Sends X4's native targeted request for the selected station's exact build module.
- Reports success only when that station confirms the exact vessel is attached.
- Live proof: Elephant verified with `attached=1`, and the active module advanced from 15% to 22%.

## Global Settings

- Adds staged settings with an explicit **SAVE GLOBAL SETTINGS** action.
- Unsaved changes are amber; committed settings show green confirmation.
- Fixes per-save persistence of the optional computer loading screen.
- Loading screen remains ON by default unless the player explicitly turns it off and saves.

## Validation and publication

- Exact GA package live-tested before Steam publication.
- All top menus remained responsive.
- Fresh log confirmed GA identity and `raw=0 decoded=OFF` with no EOC runtime, color, or interface error.
- Steam Workshop updated to version 2.99 with no dependencies.