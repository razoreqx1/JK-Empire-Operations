# EOC 3.9 TEST Build 390 — Automatic Reports State Key

**Extension version:** 490

**Date:** 2026-09-13

**Author:** RazorEQX

Build 390 preserves Build 389's event-driven live Automatic Activity and adds a compact explanation directly above it.

## Player-visible changes

- History shows live, newest-first Automatic Activity while EOC is open. New saved outcomes update the activity rows and summary bars together.
- The dashboard explains that summary bars group saved reports while the **STATE** column describes each individual live row. **Needs player** includes individual rows whose state is **BLOCKED**.
- A visible key defines **RUNNING**, **WAITING**, **BLOCKED**, **COMPLETED**, and **RECORDED** using the existing EOC colors.
- Hovering a state shows its full meaning. Hovering a shortened Current Action shows the complete action.
- Enabled automatic options use steady **RUNNING** or **ACTIVE** labels.
- Automatic report cards retain summary, full evidence, archive, and player-next-step controls.
- Optional supply-ship expansion has separate consent and spending limits. Existing eligible ships are checked first; normal blueprint, shipyard, construction-resource, payment, delivery, and assignment checks remain in force.

## Refresh and performance boundary

Automatic Activity is event-driven. It uses no polling, animation, countdown, flashing, or timer-driven redraw. Manual **Refresh Automatic Reports** remains available to resynchronize the complete retained saved history.

## Authority and safety

EOC acts only within the player's selected trade, construction-funding, ship-assignment, automatic-management, and supply-purchase permissions. It does not create free ships, bypass normal resources, silently alter station plans, or treat a purchase/order as proof of delivery.

## Runtime status

Build 389's automatic-refresh behavior and Build 390's dashboard presentation received partial live coverage. Native key geometry, state/action hover display, small-window row capacity, unexercised save/load and compatibility paths, final recovery, and empire-scale behavior remain **RUNTIME ACCEPTANCE REQUIRED** where not already observed.

See the [complete Player Guide](EOC_3.9_GA_PLAYER_GUIDE.md) and [Automatic Manager companion guide](EOC_AUTOMATIC_MANAGER.md).
