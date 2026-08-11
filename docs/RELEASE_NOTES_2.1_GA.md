# EOC 2.1 GA Release Notes

## Release identity

- Product: JK Empire Operations Center
- Release: EOC 2.1 GA
- Build: 134
- Extension version: 234
- GA flag: 1
- Steam Workshop item: 3778882957

## New in 2.1

EOC can now place one deliberate, player-confirmed, resource-backed logistics ship order internally without opening the vanilla shipyard or configuration screen.

### Medium and Large choices

- EOC checks owned blueprints and compatible player-owned shipyards.
- If both Medium and Large options are valid, the player chooses the size.
- If only one size is valid and buildable, only that size is offered.
- A size choice never submits an order.

### Three deliberate stages

1. Choose a size when more than one size is available.
2. Preview the exact hull and player shipyard.
3. Confirm the order for exactly one ship.

Preview and confirmation remain separate. No automatic or repeat production mode exists.

### Native X4 behavior

- Orders use X4's native build-task path.
- X4 generates the compatible loadout.
- Player shipyards consume normal hull and equipment resources.
- Construction scheduling and captain/crew lifecycle remain native X4 behavior.
- No free ships or resource bypasses are used.

### Duplicate protection

EOC persists a lock for the station and cargo need after submission. The protection applies across hull sizes, preventing a second order by switching between Medium and Large.

### Clearer interface guidance

The Fleet & Logistics view now tells the player exactly which action is next and clearly distinguishes size choice, preview, submission, verification, and native task acceptance.

## Validation

The release path was tested with a Large Hokkaido mineral miner. X4 accepted native task 40226, exactly one order was created, and the player-owned shipyard retained normal resource and construction control.

Build 132 completed on-load, post-action, and exit-log checks without EOC Lua or Mission Director errors. A false size-preselection state caused by a missing compatible-yard result in Build 131 was corrected before GA. Build 134 retains the tested runtime behavior, advances the release identity, and restores the full Workshop Favorite request.

## Compatibility

- X4: Foundations 8.x / 9.x
- Existing EOC installations may be upgraded in place.
- Steam Workshop and manual installation use the same JK_Station_Manager top-level extension folder.