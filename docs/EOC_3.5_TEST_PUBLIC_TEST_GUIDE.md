# EOC 3.5 TEST Build 286 — Public Test Guide

Build 286/version 3.86 is a public work-in-progress test of the on-demand Supply Model and native Station Solution Planner. Build 259 remains the last GA-qualified runtime.

## Live validation completed

The exact Build 286 runtime passed its targeted planner test at 3840x2160 with X4 UI scale 2.00. The complete planner rendered with native scrolling and showed the exact owned module, blueprint, production method, cycle output, workforce, primary-input recipe, hourly rates, storage classes, capacity calculation, evidence boundary, and player navigation. The fresh log contained no EOC widget-height rejection, Lua error, Mission Director failure, stack trace, or invalid argument in that workflow.

## Solution Planner testing

1. Load the game and wait at least 10 seconds for EOC initialization.
2. Open a persistent station/ware case in Diagnostics.
3. Complete the bounded recovery test and Expansion Readiness path.
4. Open Solution Planner and confirm the exact station and ware remain selected.
5. Compare the module, blueprint, production method, output rate, workforce, recipe inputs, and storage classes with the vanilla Station Build Plan.
6. Scroll through the complete page and verify both navigation buttons remain accessible.

The planner is advisory. It does not add modules, place plots, modify construction plans, hire builders, move cargo or credits, or bypass the vanilla editor. Plot fit, connections, builder, build-storage inventory, final price, budget, and future storage allocation remain player/X4 authority.

## Supply testing

- Supply collection runs only after a visible Run/Refresh action.
- Selector changes redraw cached results only.
- Case creation requires two explicit persistent snapshots and refuses duplicate station/ware work.
- Price and storage edits require preview, separate confirmation, native application, and immediate read-back.
- Batch pricing is limited to the selected station's valid changed buy/sell proposals and excludes storage.
- Raw Scrap remains excluded.

## Missing EOC button isolation test

If **OPEN EXECUTIVE OPERATIONS CENTER** is missing, disable every extension except EOC, fully restart X4, load the save, wait 10 seconds, and test Dock Interactions again. If EOC works alone, re-enable UI/menu mods in small groups until the smallest failing group is identified. Do not assume a specific conflict without a fresh log.

## Reporting

Report reproducible problems at https://github.com/razoreqx1/JK-Empire-Operations/issues with:

- EOC build/version
- X4 version
- Exact reproduction steps
- Relevant enabled mods
- Display resolution and UI scale for presentation issues
- A fresh exited-session debug log
