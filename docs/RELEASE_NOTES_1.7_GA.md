# EOC 1.7 GA Release Notes

EOC 1.7 GA improves Fleet & Logistics clarity, action feedback, and guided navigation while preserving player authority and EOC's evidence-based operational model.

## Startup timing

- EOC displays an immediate initialization notice after a save loads.
- Wait approximately **10 seconds** before opening EOC with **Control + H**.
- This gives the fixed initialization and player-property scan time to complete.

## Fleet and Logistics

- Adds clear registered-ship availability and operational-state presentation.
- Replaces unclear raw values such as `unknown` and `true` with player-readable status.
- Registration reports scanned, added, auto-assigned, available, and unsupported counts.
- Shipping-needs scans explain whether a compatible ship is awaiting approval and what to review next.
- Approval completion names the ship and destination and remains visible after the completed Pending row disappears.
- Empty Pending views explain when entries appear.

## Action feedback and navigation

- Operational buttons remain visibly active long enough to confirm the click was accepted.
- Repeated clicks are held while the current operation is processing.
- Actions provide explicit **STATUS** and **NEXT STEP** guidance.
- Guided redirects take the player to the relevant EOC view.
- Return navigation restores the originating page, filters, selection, and view state.
- Settings changes display immediate confirmation.

## Safety and compatibility

- Approval Required remains the deliberate assignment path.
- Auto-Assign Registered uses only eligible ships already registered with EOC.
- Managed Trade remains separately controlled by the player.
- EOC does not buy ships or intentionally take unsupported, mission-controlled, already assigned, or player-controlled craft.
- Compatible with X4: Foundations 8.x and 9.x.

## Upgrade

Steam Workshop subscribers receive the update automatically. Manual users should replace the existing `JK_Station_Manager` folder with the 1.7 GA folder, then restart X4. After loading a save, wait approximately 10 seconds before opening EOC.
