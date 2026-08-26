# EOC 3.9 GA — Build 339

## Command-first decisions

- Cases, Guided Recovery, and Solution Planner lead with the conclusion, one next instruction, and the primary action.
- Technical evidence remains available behind exact-case Deep Dive controls.
- Deep Dive open and close preserve the exact case context and return correctly.

## Background verification ownership

- The player requests verification once; EOC retains the exact station, subject, severity, and amount baseline.
- The next completed established empire-analysis cycle performs the comparison automatically.
- EOC reports `IMPROVING`, `UNCHANGED`, `WORSENING`, or an honest `BLOCKED` result through a notification, Logbook entry, and retained UI state.
- Acceptance and in-progress messages warn against entering Station Build mode; `TEST COMPLETE` explicitly releases that restriction.
- Player prompts to certify a meaningful cycle, return later, repeat verification, request another check, or keep a page open were removed.

## Presentation, evidence, and capacity

- Variable-length EOC lists use adaptive page boundaries based on the available viewport and X4's shared row limits.
- Dynamic fleet-capacity evidence is observation-only, bounded, persistent, confidence-labelled, and honest while still learning.
- Supply, trade, logistics, Cases, and Reports retain exact identity, evidence limits, duplicate protection, and return context.

## Authority and performance

- Background verification uses EOC's existing bounded empire-analysis cadence.
- No new watcher, countdown, scheduler, per-frame hook, free ship, resource bypass, unauthorized construction, cargo movement, credit movement, or expanded gameplay authority was added.

Build 339 is the identity-only GA promotion of the RazorEQX runtime-accepted Build 338 behavior. Compatible with X4 8.x and 9.x.
