# EOC 1.7 GA User Guide

## Start EOC safely

1. Load your save.
2. EOC displays an initialization notice immediately.
3. Wait approximately **10 seconds** for initialization and the player-property scan to complete.
4. Press **Control + H** and open the EOC Management Window.

The short wait is expected. It prevents EOC from being opened before its initial station and property data are ready.

## Main tabs

- **Stations** - station roles, operational controls, and station reports.
- **Overview** - empire health, KPIs, trends, and recent changes.
- **Fleet & Logistics** - registered ships, shipping needs, pending approvals, and EOC trade-order review.
- **Diagnostics** - guided recovery, suppliers, stabilization evidence, probes, and verification.
- **Cases** - active operational issues ordered by importance.
- **Reports** - completed EOC report history.
- **Global Settings** - trade authority, ship-assignment authority, and station-role automation.

## Authority settings

### Trade Order Control

- **Advisor Mode** gives instructions only.
- **Managed Trade** permits EOC to create evidence-supported EOC trade offers.

### Ship Assignment Authority

- Disable ship assignment if you do not want EOC to assign ships.
- **Approval Required** creates a pending proposal for you to inspect and authorize.
- **Auto-Assign Registered** lets EOC assign only eligible ships already registered with EOC.

Every settings change displays a status confirmation at the top of Global Settings.

## Register ships and scan needs

1. Open **Fleet & Logistics**.
2. Select **Register Suitable Unassigned Ships**.
3. Wait for the button feedback and read the **STATUS** line.
4. Review **Registered Ships** if directed there.
5. Select **Scan Shipping Needs**.
6. Read the resulting **STATUS** and **NEXT STEP** lines.

Registration does not mean every registered ship is immediately needed. A ship may remain available until EOC finds a compatible, supported station need.

## Approval Required workflow

1. Run **Scan Shipping Needs**.
2. When EOC finds a supported need and compatible ship, open **Pending**. Guided navigation may take you there automatically.
3. Review the exact ship, destination station, and operational reason.
4. Select **Authorize Pending Assignment** only if you approve it.
5. After completion, the Pending row disappears and a named completion message remains visible.
6. Use the return path to go back to the view where you started.

## Auto-Assign workflow

1. In Global Settings, select **Auto-Assign Registered**.
2. Register eligible ships.
3. Run **Scan Shipping Needs**.
4. Review the status message and Registered Ships list.

EOC assigns only when it has both a supported need and a compatible eligible ship. An available ship is not evidence that a station currently needs it.

## Action feedback and navigation

Operational buttons intentionally remain in their active color briefly. This confirms the input was accepted and discourages repeated clicking while the operation runs.

- **STATUS** explains what EOC completed or found.
- **NEXT STEP** explains where to go or what to review.

If an action redirects you, EOC provides a return path and restores the relevant page, filters, selection, and view state.

## Trade orders and station roles

**Review EOC Trade Orders** inspects offers owned by EOC; it does not claim unrelated player or third-party orders. Managed Trade is independent from ship assignment.

EOC uses station roles to interpret evidence. Review Stations for any role marked undefined. **Assign Undefined Station Roles** changes only player stations currently undefined and reports whether any were found.

## Troubleshooting

- If EOC seems incomplete immediately after loading, close it, wait until the 10-second initialization period has passed, and reopen it.
- If Pending is empty, EOC has no supported need with a compatible registered ship awaiting approval.
- If ships remain available, this may be correct; registration does not create artificial demand.
- If an action is processing, wait for the active-button feedback, STATUS, and NEXT STEP before clicking again.
- For issue reports, include the X4 version, EOC version, preceding action, screenshot, and relevant debug-log section.
