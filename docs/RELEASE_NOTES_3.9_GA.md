# EOC 3.9 GA - Build 350

## Plain module-count planning

- Solution Planner now leads with a best-current estimate of how many production modules to add for every supported native ware chain.
- The estimate uses a bounded generic recipe cascade; it is not hardcoded to Food Rations, Wheat, or any other single resource.
- Final-output duplicate guards, installed and planned production, shared upstream demand, and terminal raw-source boundaries remain visible.
- Advanced readiness, evidence, native recipe, and production math remain available on paged Deep Dive views.

## Player plan calculator and safety gates

- Players can enter the number of each module they intend to add and press **TAB after each number** to commit the field.
- **CHECK MY MODULE PLAN** compares the entered plan with EOC's current estimate.
- Checks cover underbuild, overbuild, workforce capacity, storage pressure, missing recipes, and raw-resource requirements.
- Estimates remain advisory and approximate. EOC does not place modules, change the vanilla Station Build Plan, or spend construction resources.

## Persistent agreed build lists

- A checked matching plan can be saved as the agreed build list for the exact station and production subject.
- The list remembers module counts, explicit zero-count duplicate guards, raw-source requirements, and current safety conditions.
- Saved lists remain available after closing EOC and after save/reload, including from a no-case Solution Planner index.
- The saved view shows agreed counts, approximate added/planned progress, and how many modules are still needed.
- Real evidence changes mark the plan for review without silently overwriting it.
- Players can explicitly replace the list with a newly checked agreement or clear it through confirmation.
- Build 350 includes the accepted correction for the immediate false **PLAN NEEDS REVIEW** warning caused by an absent optional zero-count guard.

## Player-first menus introduced in Build 344

- Every main EOC page now begins with a **START HERE** guide.
- Each guide explains what the page does, gives short ordered steps, and says when the player is finished.
- Player-facing wording is written for a capable 15-year-old reader without removing honest evidence limits.
- Technical evidence remains available behind exact-case Deep Dive controls.

## Jobs and background verification

- Player-started jobs retain a result that says what happened, what it means, and exactly what to do next.
- Waiting states tell the player to continue normal play, avoid Station Build mode when required, and not start the same job again.
- Completed background-test states tell the player to stop, wait, fix a named condition, refresh missing information, or run one new test only after the required change.
- Completed-test buttons follow the displayed next action instead of immediately repeating the same test.
- Results continue to return through EOC, notification, and Logbook routes supported by each workflow.

## Display and compatibility

- Unsupported separators are converted to plain display text at shared UI boundaries.
- Saved state, evidence keys, comparison strings, and gameplay logic remain unchanged by display cleanup.
- Adaptive row budgeting reserves space for the new page guides while respecting X4's shared table limits.

## Authority and performance

- Unknown information remains unknown; EOC does not claim success without evidence.
- No watcher, countdown, polling loop, scheduler, per-frame hook, free ship, resource bypass, unauthorized construction, cargo movement, credit movement, or expanded gameplay authority was added.

Build 350 is the identity-only GA promotion of the RazorEQX runtime-accepted Build 349 behavior. Compatible with X4 8.x and 9.x.
