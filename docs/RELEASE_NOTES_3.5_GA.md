# EOC 3.5 GA Release Notes

EOC 3.5 GA advances the public release to Build 304 / extension version 4.04.

## Planning and supply

- Native Station Solution Planner evidence for exact modules, blueprints, methods, output, workforce, recipe inputs, storage classes, and recommended capacity.
- Bounded native scrolling and same-page context preservation.
- Explicit/on-demand Supply collection, persistent two-snapshot case handling, duplicate prevention, and guarded price/storage confirmation.
- Raw Scrap remains excluded from conventional Supply recommendations.

## Exact raw-resource mining

- Native `MiningRoutine` assignment with exact ware-basket and one-entry manual-override read-back before EOC claims a resource pin.
- Persistent station/ware assignment records and final Planner feedback.
- Rapid duplicate suppression and one-full-refresh disabled action feedback.
- Slow bounded management: one station per five-minute cycle, at most one assignment change per cycle, and evidence-gated growth to no more than three miners per resource.
- Auto, Approval Required, and Disabled authority modes remain separate.

## Player-control boundaries

- No free or automatically purchased ships.
- No stealing or repurposing assigned ships.
- No hidden resource creation or bypass.
- No unauthorized construction, plot, cargo, or credit action.
- Ordinary traders retain native station-manager behavior.

## Acceptance

The promoted runtime passed live Planner presentation, assignment feedback, rapid duplicate handling, exact Helium pinning through native MiningRoutine read-back, persistent result display, and bounded five-minute manager observation. Build 304 corrects the stale startup notification to display the current GA identity and otherwise preserves the accepted runtime.
