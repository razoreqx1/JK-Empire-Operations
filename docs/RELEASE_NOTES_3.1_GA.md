# EOC 3.1 GA Release Notes

EOC 3.1 GA promotes the runtime-validated Dock Interactions event path while preserving EOC 3.0 GA behavior and player control.

## New and updated

- Records successful one-time DockedMenu callback registration.
- Records when Dock Interactions renders the EOC button.
- Records player selection of **OPEN EXECUTIVE OPERATIONS CENTER**.
- Records the Lua open-event raise and Mission Director receipt.
- Keeps the startup registration retry bounded and stops immediately after successful registration.
- Adds no permanent or recurring watchdog.

## Runtime validation

Build 217 supplied the tested source for this release. Live X4 evidence confirmed the ordered callback-registration, button-render, button-click, open-event-raise, and open-event-receipt chain. No EOC Lua or runtime failure signature was found.

## Safety and compatibility

No automation, trade, shipping, construction, KPI, save-data, or player-authority behavior was changed. EOC supports X4 8.x and 9.x and does not require UI Extensions and HUD.
