# EOC 2.8 GA User and Support Guide

## Open EOC

1. Load the game and wait about 10 seconds for initialization.
2. Open **Dock Interactions** from the top HUD menu.
3. Select **OPEN EXECUTIVE OPERATIONS CENTER**.

EOC includes its own Dock Interactions integration. **UI Extensions and HUD is not required.** The separate EOC pinwheel remains available as a navigation and return layer.

## Station construction

Open **Construction** or use a station's construction shortcut. EOC shows:

- The ordered module queue and current progress.
- Whether X4 reports a construction vessel attached.
- Assigned build-storage traders.
- The live construction budget and exact X4-reported shortfall.
- Every currently missing construction ware and amount.

Under **Approval Required**, EOC asks before replacing an occupied construction vessel's current role. Under **DO IT ALL**, EOC may fund an exact verified construction-account shortfall and reassign an eligible construction vessel automatically.

EOC uses X4's native builder workflow. It detaches the selected construction vessel, targets the selected station's exact build request, and reports success only after the station confirms that exact vessel. It does not create a free ship or bypass construction resources.

## Global Settings and startup screen

The computer loading screen is visual only; scanning and analysis continue whether it is ON or OFF.

1. Open **Global Settings**.
2. Select the loading-screen setting. A changed selection becomes amber.
3. Select **SAVE GLOBAL SETTINGS**.
4. Green **GLOBAL SETTINGS SAVED** confirms the committed value.

The preference is stored per save. It defaults to ON for new players and existing saves that have never changed it. One player's OFF preference cannot change another player's game.

## Guided Recovery and cases

Use **Diagnostics** for the first supported blocker, evidence, one recommended action, and fresh verification. EOC does not claim recovery from missing evidence. Player investigations, monitored cases, and duplicate prevention remain bounded to their exact station and subject.

## Managed actions and safety

- Preview does not submit an action.
- Amber indicates an unsaved choice or a confirmation that still requires player approval.
- Construction funding uses only X4's exact reported shortfall and only under the selected authority.
- EOC does not alter a station build plan, cancel ordinary player orders, create free ships, or bypass resources.
- Other automatic trading or ship-management mods can compete for the same ships. If reassignment repeats, disable one automation system or use Approval Required.

## Save safety and removal

EOC is designed so a save never depends on the mod. It does not add permanent custom ships, stations, wares, sectors, or other custom assets required for loading. Its operational actions use X4's normal objects, accounts, orders, and construction systems.

You do not need to uninstall EOC before updating. If you later remove EOC, the save and normal X4 assets remain intact. For a clean handoff, finish or cancel any pending EOC confirmation before removal; ordinary X4 orders already accepted by the game remain ordinary X4 orders.

## Troubleshooting

- Wait about 10 seconds after loading before opening EOC.
- If construction is stalled, confirm the plan, builder, budget, build-storage access, and missing wares on the Construction page.
- Use **Refresh Construction Status** after changing funds, wares, or builder state.
- If another automation mod keeps changing a ship's role, switch EOC to Approval Required or disable the competing automation.
- When reporting a problem, include the EOC build/version, the affected station or ship, a screenshot, and the X4 `debuglog.txt` from that session.

## Current release

EOC 2.8 GA is Build 199/version 299. It was live-tested as the exact package published to Steam. The targeted Elephant assignment was confirmed by X4 and the active station module advanced from 15% to 22%.