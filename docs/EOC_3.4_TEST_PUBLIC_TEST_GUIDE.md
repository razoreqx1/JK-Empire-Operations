# EOC 3.4 TEST Build 265 — Public Test Guide

Build 265/version 3.65 is a public work-in-progress test. It contains the on-demand Supply Model, Advisory Expansion Planner, selected-station resource filters, and a bounded Dock Interactions compatibility experiment.

## Missing EOC button isolation test

The developer reproduced a clean standalone environment by disabling every other mod. With only EOC enabled, the EOC button appeared and every EOC menu opened successfully.

Players who cannot see **OPEN EXECUTIVE OPERATIONS CENTER** should test the same way:

1. Confirm EOC shows version 3.65 in the Extensions screen.
2. Disable every extension except EOC.
3. Fully restart X4.
4. Load the affected save and wait at least 10 seconds.
5. Open Dock Interactions and look for **OPEN EXECUTIVE OPERATIONS CENTER**.
6. Open EOC, visit every top-level menu, close EOC, and open it again.
7. Exit X4 normally and preserve the fresh debug log.

If EOC works alone, re-enable UI/menu-related mods in small groups until the button disappears. Report the smallest group that reproduces the problem and attach the fresh debug log. This identifies an environmental conflict without guessing which mod is responsible.

## Supply and Expansion testing

- Supply collection runs only after a visible Run/Refresh action.
- Selector changes redraw cached results only.
- Compare displayed values and deltas with the selected station's current X4 information.
- Price and storage changes require preview and separate confirmation.
- The Expansion Planner is advisory. It does not place plots, alter build plans, construct modules, create resources, or move credits/cargo.

When reporting a problem, include the EOC build/version, X4 version, exact reproduction steps, enabled UI/menu mods, and a fresh debug log.
