# EOC 2.4 GA User Guide

## Open EOC

1. Load the game and wait about 10 seconds for initialization.
2. Open **Dock Interactions** using the icon immediately to the right of Diplomacy.
3. Select **OPEN EXECUTIVE OPERATIONS CENTER**.

EOC does not depend on Ctrl+H. The separate EOC pinwheel remains available as a navigation and return layer.

## Name your command intelligence

On first EOC use for a new or existing save, choose the intelligence name. The name persists with the save and can later be changed under **Global Settings**.

## Follow Guided Recovery

1. Open **Diagnostics** and select the working station and case.
2. Read **Next Action** for the first unresolved blocker and one recommended player action.
3. Open **Evidence Details** for the measurements supporting the diagnosis.
4. When offered, open **Recovery Options** to review a bounded market-path test.
5. Preview first. Amber means confirmation is still required and nothing has been submitted.
6. Confirm once. EOC locks repeat submission and keeps the result visible.
7. After an operating or delivery cycle, run **Verify Result** for a fresh comparison.

Verification reports **Resolved**, **Improving**, **Unchanged**, or **Worsening**. EOC does not claim success merely because an action was opened.

## Use a bounded NPC market test

A supported recovery case may offer one bounded NPC-enabled BUY or SELL test. The test:

- Uses the exact station and ware from the diagnostic case.
- Creates one evidence-sized EOC-owned offer.
- Does not change the existing ware-specific trade rule.
- Does not alter ordinary station offers.
- Requires Preview and an amber Confirm action.
- Can be removed through **REMOVE EOC TEST / DO NOTHING**, followed by its amber confirmation.
- Locks after completed creation and removal attempts to prevent repeat submissions.

## Make a successful test permanent

EOC never converts a bounded test into permanent policy automatically. To retain the tested NPC path:

1. Open the station **Logical Overview**.
2. Select the tested ware's buy or sell offer.
3. Change only that ware's trade rule to permit the intended NPC suppliers or customers.
4. Do not change a station-wide rule unless you intend the wider effect.
5. Remove the temporary EOC test offer after adopting the permanent ware-specific rule.

## Read the Stations page

The Stations page separates the station list, persistent EOC role, and advisory operating policy. Green is current, amber is awaiting confirmation, gray/blue is available, and red is unavailable. Role and policy changes require two deliberate clicks.

## Build a saved fleet

1. Open **Fleet & Logistics**, then **Fleet Management**.
2. Create or edit a named fleet template.
3. Add owned blueprints and bounded quantities.
4. Choose one compatible player shipyard or distribution across compatible owned yards.
5. Preview the plan. Preview places no orders.
6. Confirm only when the amber plan is correct.

## Safety boundaries

- No free ships or resource bypass.
- No automatic or repeating production.
- No automatic credit movement.
- No automatic conversion of market tests into permanent policy.
- Owned blueprints and compatible player shipyards only.
- X4-generated loadouts and native captain/crew lifecycle.
- Preview never submits an action.
- Duplicate submissions remain blocked.