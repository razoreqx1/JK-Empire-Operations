# EOC 3.9 GA — Build 369

## Player-first update

- New task-first Home, Stations, Plans, History and Settings; existing specialist tools and ship building remain under All Tools.
- Independent production scenarios with owned recipes, module-count or hourly-output targets, and external-supply or dedicated-support assumptions.
- In-page station selection preserves recipe/quantity intent and invalidates old calculated results.
- More visible recipes, explicit quantity labels, next-action arrows and clearer return navigation.
- Saved player scenarios are advisory snapshots, separate from evidence-backed repair plans and their progress workflow.

Scenarios do not construct modules, spend credits or order ships. External input supply is assumed, not verified. Raw resources require mining or trade. Workforce, storage, throughput, costs and placement remain player review items.

Build 369 is an identity-only GA promotion of Build 368. Maintainer live review confirmed the revised UI and station-switch draft retention; reviewed logs contained no EOC exceptions. This is not universal runtime coverage: save/reload, all display sizes, every navigation branch and fresh subscribed delivery remain unverified.

## Preserved Build 366 delivery correction

Root UI registration remains catalog-delivered with the Steam MD/Lua payload. The dock substitution and all existing operational features are retained.

## Historical Build 364 release notes

Build 364 retains the complete Build 359 GA foundation and adds the operational-clarity work exercised during the Build 361 walkthrough, Build 362's truthful raw-resource classification and identity correction, and Build 363's more resilient dock-access bootstrap.

## Operational clarity

- Construction now provides an empire-wide overview with blocked stations first, explicit funding/ware/builder states, bounded paging, and optional idle-station visibility.
- Cases clearly distinguish **VIEW CASE** from **CREATE INVESTIGATION**, and exact station/subject deduplication remains intact.
- Fleet route-state meanings are explained and station, registered-ship, trade-activity, and pending-assignment columns remain aligned.
- Supply navigation, selected-station cache ownership, raw-resource identity, resource cards, and production-versus-storage language are clearer.
- Feedback rows retain stable selectable geometry across repeated actions.
- KPI Storage Levels supports exact station and physical storage-type filtering.

## Raw resources and dock access

- SOLID and LIQUID raw resources are labeled as mining or trade sources instead of station production-module candidates.
- Raw-source planning directs players to stock movement, mining coverage, reachable offers, and trade permissions; manufactured wares retain the Station Build Plan boundary.
- The cataloged DockedMenu now owns one direct EOC access row and raises the established EOC open event without depending solely on extension `ui.xml` startup.
- The existing adapter adopts that integrated owner without adding a duplicate button and retains its bounded compatibility route for a later replacement owner.
- The maintainer's current game and EOC setup run normally, but the public missing-button condition cannot be reproduced locally. Affected players should report their field result and attach `debuglog.txt` if the button remains unavailable.

## Evidence boundary

- The Build 361 walkthrough rendered the new Construction, Cases, Fleet, Supply, feedback, and KPI views without EOC Lua/MD/widget/table/callback faults.
- Build 362 raw-resource wording and the catalog-owned dock correction remain dependent on affected-player field evidence and are not described as runtime-proven fixes.
- No new watcher, polling loop, hidden scan, gameplay authority, construction action, free ship, cargo movement, or credit movement was added.

## Build 359 foundation retained

Build 359 was the identity-only GA promotion of the RazorEQX runtime-accepted Build 358 behavior. Build 364 preserves its guided-planning, case-disposition, save-safety, salvage-tug, logistics-evidence, and saved-scenario refresh work.

## Guided planning and honest project scenarios

- Workforce, habitat-module counts, and workforce-provision information are separated so station-wide provision wares cannot masquerade as one habitat requirement.
- Zero-count habitat inputs are omitted from the simple calculator.
- Unknown habitat-to-species mapping remains unknown instead of being guessed.
- When project demand cannot be measured, EOC does not invent a required final-output count. The player may instead open a clearly labeled scenario for a chosen final-output count and review the generic support chain.
- EOC continues to lead with plain best-current module counts, use a bounded native-recipe cascade, and retain paged advanced readiness, evidence, recipe, and production math.

## Safe agreed build lists

- The Save callback rechecks the live calculator state and refuses stale, dirty, missing, nonconverged, or mismatched results instead of saving old counts.
- Rejected saves provide explicit TAB-and-recheck guidance.
- Zero-warning plans persist an explicit empty safety-condition list, and legacy plans missing that property remain readable.
- Saved player scenarios are recognized from the persisted plan after reopen without depending on a currently loaded calculator or readiness flag.
- The exact visible saved-list screen receives bounded automatic progress refresh and an explicit **REFRESH PROGRESS NOW** control.
- Manual completion redraws the saved list even when the station fingerprint is unchanged.
- Command, calculator, Deep Dive, readiness, checklist, and unsaved-draft Solution Planner screens remain refresh-disabled. Leaving the saved-list screen immediately removes monitoring eligibility.
- Agreed counts, zero-count duplicate guards, raw-source requirements, safety conditions, approximate added/planned progress, remaining counts, explicit replacement, confirmed clear, and no-case/save-reload access remain preserved.

## Player-requested case disposition

- When fresh analysis finds no current problem for an exact player-requested investigation, the terminal result offers **CLOSE THIS INVESTIGATION** and **KEEP THIS INVESTIGATION OPEN**.
- Close removes only that exact player request while preserving current EOC observation evidence.
- Keep returns without mutation.
- A terminal no-match result no longer presents a misleading advancing action.

## Registered Manticore salvage-tug coverage

- EOC recognizes operational unassigned player salvage tugs through X4's native salvage purpose and tug ship type.
- Station need uses native processing-module and salvage-subordinate evidence.
- Disabled, Approval Required, and Auto-Assign Registered authority modes remain distinct.
- Assignment revalidates exact ownership, operational state, tug type, registration, commander state, and station need at mutation time.
- EOC assigns only one exact registered tug, prevents duplicate station tug assignment, and waits for native commander plus salvage-assignment readback before reporting success.
- EOC never creates a free tug, repurposes an ineligible ship, bypasses resources, or claims that registration alone proves assignment.

## Readable logistics evidence

- Fleet & Logistics resource cards now lead with concise stock, target, work/wait/block, assignment, activity, eligibility, source, last-movement, and next-action evidence.
- A read-only **VIEW ASSIGNED SHIPS** route pages transported station-subordinate names eight at a time.
- Every ship row retains the **SHARED POOL — UNPROVEN** boundary. Membership in a station pool is not proof that one ship serves the selected ware.
- The evidence view provides no reassignment control.

## Authority, compatibility, and performance

- EOC remains advisory in Solution Planner. It does not place modules, modify the vanilla Station Build Plan, spend credits, or bypass construction resources.
- No new independent scheduler, hidden scan, watcher, polling loop, countdown, per-frame hook, free ship, resource bypass, unauthorized construction, cargo movement, or credit movement was added.
- Existing persistent schemas, transport indices, generic cascade, fleet templates, managed trade ownership, native mining pins, construction boundaries, and player-selected authorities remain intact.
- Compatible with X4 8.x and 9.x.

## Project status

EOC is complete. Future major development will move to a separately planned mod that RazorEQX will announce when it is complete and ready to share.

EOC remains maintained. Bug reports and feature requests are welcome, and compatibility updates, bug fixes, and carefully considered improvements will continue for the foreseeable future.
