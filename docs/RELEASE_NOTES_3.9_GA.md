# EOC 3.9 GA - Build 344

## Player-first menus

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

Build 344 is the identity-only GA promotion of the RazorEQX runtime-accepted Build 343 behavior. Compatible with X4 8.x and 9.x.
