# EOC Developer Architecture Guide

## Purpose

This guide is the entry point for programmers working on EOC. It describes ownership, persistent schemas, data flow, safety invariants, X4-specific constraints, and the validation lifecycle. Historical build identifiers in symbol names are intentionally retained for save compatibility.

## Runtime layers

1. `md/JK_Station_Manager.xml` performs the authoritative empire scan and constructs the station directory plus current Critical and Warning cases.
2. `md/JKEOC_Operational_Intelligence.xml` retains bounded multi-sample evidence in SPOS.
3. Advisor/remediation/trade/shipping/fleet XML files derive recommendations and execute only authority-bounded actions.
4. `md/JKEOC_Settings_Interface.xml` is the ABI between Mission Director and Lua. It serializes persistent records into positional arrays and validates commands returning from Lua.
5. `ui/eoc_settings.lua` renders the full window and owns transient navigation only.
6. `subst_01.cat/.dat` provides EOC's self-contained Docked-menu owner. `ui/eoc_personal_office.lua` registers the access button through its callback table and raises the one-shot open event.

## File ownership map

- `JK_Station_Manager.xml`: station discovery, cargo/workforce/construction facts, current cases, focus workflow, baseline periodic scan.
- `JKEOC_Operational_Intelligence.xml`: SPOS record identity, recurrence, confidence, retention, rotation, recovery, and resolution.
- `JKEOC_Executive_Advisor.xml`: persistent station profiles, roles, executive and station reports.
- `JKEOC_Executive_Intelligence.xml`: bounded dashboard aggregation from existing profiles and evidence.
- `JKEOC_Operational_Remediation.xml`: evidence-to-remediation lifecycle and teaching records.
- `JKEOC_Trade_Order_Manager.xml`: EOC-owned trade offers and action-status reconciliation.
- `JKEOC_Shipping_Control.xml`: registered-ship discovery and authority-gated assignment.
- `JKEOC_Global_Fleet_Minimums.xml`: global minimum policy and one-at-a-time fulfillment.
- `JKEOC_Shipyard_Intelligence.xml`: bounded shipyard lifecycle observation.
- `JKEOC_Autonomous_Stabilization.xml`: bounded advisory stabilization presentation.
- `JKEOC_Settings_Interface.xml`: MD/Lua transport, command validation, Clear All, reports, and refresh events.
- `eoc_settings.lua`: rendering, UI events, page state, scroll preservation, and player command submission.
- `eoc_personal_office.lua`: bounded callback registration and one-shot EOC open-event bridge.
- `subst_01.cat/.dat`: native X4 substitution catalog containing EOC's Docked-menu owner. It preserves an existing callback table when another compatible UI owner loaded first, isolates callback failures, and does not add polling or per-frame repair.

## Principal persistent schemas

### `global.$JKEOC_StationDirectory`

One record per valid player station. Contains station identity, role/profile inputs, product/resource/trade-ware lists, current cases, cargo capacities, workforce facts, assigned-ship counts, construction facts, and station funds.

### `global.$JKEOC_CriticalCases` and `global.$JKEOC_WarningCases`

Current EOC-owned operational cases. Important members include station/stationname, type, ware/wareobject, amount/target/maximum, storage facts, production facts, supplier counts, compatible trader counts, station money, root cause, corrective action, and construction evidence.

`global.$JKEOC_PlayerCases` is separately player-owned. Cleanup and migration must not delete it unless the player explicitly requests that behavior.

### `global.$JKEOC_SPOSRecords`

Retained observation evidence, capped at 256 records. Identity is station + category + subjectkey. Tracks samples, hits, state, confidence, first/last seen times, recurrence, relapse, recovery, resolution, evidence text, cause, recommendation, verification, and player-wait state.

### `global.$JKEOC_B73Offers`

Only EOC-created trade offers: offer handle, station, ware, direction, amount, creation time, baseline, target, verification, and optional market-test metadata. Removing an entry may remove its live offer; never infer ownership from station/ware alone.

### `global.$JKEOC_B241ActionStatus`

UI-facing reconciliation state for managed actions: station, ware, direction, amount, state, reason, waiting condition, baseline, target, creation time, current value, and movement verification.

### `global.$JKEOC_B243ChecklistProgress`

Persistent player/EOC checklist state keyed by station, case type, subject, playbook, schema, and step. Player responses are reports, not verified game evidence.

### `global.$JKEOC_B67Profiles`

Persistent station executive profiles: identity, role, health, trend, confidence, priority, recommendation, active counts, assignment counts, construction/workforce/storage summaries, and retained-history classifications.

## Critical invariants

- E: is installation only, never a source workspace.
- Player clicks request work; they do not prove completion.
- Player-created investigations remain distinct from EOC-owned cases.
- EOC removes only trade offers it owns and records.
- Raw Scrap is an X4 infinite sink. Do not create conventional shortage cases, BUY actions, supplier/local-production advice, or checklists for `ware.rawscrap`.
- Continue observing recycling stations, outputs, Energy Cells, Scrap Metal, and every other ware.
- No free ships, credits, resources, or hidden gameplay bypasses.
- No new watcher, polling loop, per-frame scan, or duplicate recurring scheduler.
- Automatic refresh and same-page actions preserve visible scroll position.
- Button wrappers must not rebuild a page before the handler updates state.
- Never combine a multi-return Lua `pcall` with `and` when both returned values are needed.

## Mission Director to Lua ABI

The settings interface sends positional arrays because that is the established X4 event transport. Lua uses index-based access. Treat each array layout like a binary ABI:

- Document new positions at both producer and consumer.
- Prefer appending fields over inserting them.
- Update defaults for older or missing records.
- Verify every page consuming the changed array.
- Never replace stable object identity with a display name.

## Historical identifiers

Names such as B67, B73, B241, B243, V450, and V600 identify the schema or subsystem version in which a contract was introduced. They may appear in the current build and should not be globally renamed. Current release identity is controlled separately by `content.xml`, the startup marker, Lua `EOC_OS_BUILD`, and release notes.

## Safe change workflow

1. Copy the latest preserved source into a new build directory.
2. Make the smallest evidence-supported change.
3. Inventory every function/cue crossed by a ranged edit.
4. Update build/version/channel/date identities consistently.
5. Parse all XML files.
6. Run Lua compiler/parser validation when available; otherwise report unavailability.
7. Scan for literal PowerShell backtick-newline corruption.
8. Package with one `JK_Station_Manager/` root.
9. Extract uniquely and compare every file hash to source.
10. Delete and confirm deletion of the extraction snapshot.
11. Require live X4 and copied-debug-log proof before promotion.

## Debug logging

EOC uses `[JKEOC][B…][EVENT]` markers. Some Lua diagnostics use `DebugError` so X4 labels successful diagnostic lines as errors; judge the event text, not the prefix alone. Always distinguish EOC failures from unrelated game or third-party-mod messages.
