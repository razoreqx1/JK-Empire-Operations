# EOC 2.0 GA Release Notes

EOC 2.0 GA reorganizes the major operational workflows around a simple decision pattern: one conclusion, one next player action, optional supporting evidence, and a truthful verification result.

## Clearer decisions

- Overview leads with the empire conclusion and one recommended route.
- KPI Center identifies the first station worth reviewing without implying that its score authorizes action.
- Fleet & Logistics states whether approval, ship registration, or no change is required.
- Station pages show the first case to handle and route the player to the guided workflow.
- Cases display the current blocker and next action before supporting results.
- Reports preserve the completed finding and return the player to the originating workflow.
- Global Settings explains the authority being granted before presenting controls.

## Truthful case reasoning

- Import-only cases treat local production and local production inputs as **not applicable**.
- Passing prerequisites no longer produce unsupported construction, storage, ship, or funding recommendations.
- Evidence is explicitly labeled as a snapshot from the last EOC analysis.
- Missing scan time never produces a malformed display symbol.

## Safe asynchronous actions

- Reports remain unavailable from submission until EOC confirms that the report was saved.
- Analysis, scans, registrations, approvals, role and policy changes, and proofs retain deterministic working/result states.
- Navigation remains available while operational work is pending.
- The legacy trader-order cancellation supply action remains unexposed.

## Verification

Guided Recovery retains real rescanning and reports **RESOLVED**, **IMPROVING**, **UNCHANGED**, or **WORSENING** for the working case.

## Compatibility and upgrade

EOC 2.0 GA supports X4: Foundations 8.x and 9.x. Steam Workshop subscribers receive the update automatically. Manual users should replace the existing JK_Station_Manager folder, restart X4, load a save, and wait approximately 10 seconds for EOC initialization.