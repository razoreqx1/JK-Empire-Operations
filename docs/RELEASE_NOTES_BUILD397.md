# EOC 3.9 TEST Build 397 Release Notes

**Extension version:** 4.97

**Engineering build:** 397

**Release identity shown in game:** `EOC - EOC - VERSION 497 (BUILD 397)`

Build 397 focuses on clean case lifecycle management and a deliberate, native construction handoff.

## Case and planner cleanup

- Archives active cases only when EOC can prove they are resolved or the player explicitly closes them.
- Keeps uncertain, waiting, current, and unresolved cases active.
- Shows one active row for each exact station/subject pair and prevents duplicate case creation.
- Retains a bounded archive of up to 64 resolved cases instead of stacking stale work into the active list.
- Reconciles player-created investigations with EOC cases without losing ownership or evidence boundaries.
- Clears the previous case's planner transaction when a different case is opened, preventing inherited station, product, count, quote, or confirmation state.

## Exact production expansion workflow

- Keeps the calculator advisory: a calculated or saved scenario does not queue construction.
- Saves an exact player-selected module list separately from evidence-backed EOC demand.
- Prepares a native expansion quote for the exact station and module count.
- Requires a separate, time-bounded player confirmation before construction is queued.
- Redirects only an exact successful `QUEUED` result to that station's construction-progress page.
- Does not redirect on canceled, expired, blocked, or failed confirmation states.
- Preserves normal X4 funding, builder, construction-ware, placement, and completion requirements.

## Visible identity

- Displays the release and engineering build at the top of EOC so screenshots and runtime reports can be matched to the installed build.

## Live acceptance completed

The exact Build 397 route was accepted in live X4 testing with **Smart Chip Production** at **Razors Edge HQ Two**:

1. The Smart Chips case opened the correct diagnostic calculator.
2. One Smart Chip Production module was saved.
3. EOC prepared the exact expansion quote.
4. Explicit player confirmation queued the native construction plan.
5. EOC opened the exact station's construction-progress page.
6. The player separately approved the construction funds.
7. X4 assigned a builder, construction wares became met, and the module entered active construction.

This acceptance proves that exact route. Other native or compatibility-dependent paths remain subject to their own runtime evidence.

## Safety boundaries

- No scenario calculation, saved list, or quote alone changes the station plan.
- EOC does not create free credits, ships, cargo, wares, blueprints, modules, or stations.
- Confirmation queues normal X4 construction; it does not prove completion.
- Funding and logistics remain visible, separate steps unless the player's selected authority explicitly permits them.
- Existing automatic-manager safeguards and Build 390 behavior are retained.

Report issues at <https://github.com/razoreqx1/JK-Empire-Operations/issues> and include the displayed EOC build/version, exact steps, affected station and ware, and the copied X4 debug log.
