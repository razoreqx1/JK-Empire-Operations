# EOC 3.9 GA Player Guide

**Applies to:** EOC 3.9 GA, Build 369, extension version 469
**Game:** X4: Foundations 8.x / 9.x

EOC turns empire data into three practical answers:

1. What needs attention?
2. What should I do next?
3. Is EOC advising me, waiting for approval, or allowed to act?

The Build 369 interface is organized around player tasks. The main tabs are **HOME**, **STATIONS**, **PLANS**, **HISTORY**, **SETTINGS**, and **ALL TOOLS**. Specialist tools still exist under **ALL TOOLS**.

---

## 1. Important rules

- A displayed result is evidence or advice, not proof that X4 completed an action.
- **UNKNOWN** or **UNVERIFIED** means EOC does not have enough evidence. It does not mean zero, safe, or complete.
- A saved production scenario is an advisory snapshot. It is not construction approval and does not modify the X4 Station Build Plan.
- EOC never creates free ships, credits, cargo, resources, blueprints, modules, or stations.
- Press **TAB** after changing a number so the menu commits the value.
- Follow the steady **> NEXT:** control when a page presents a sequence.
- A button marked **opens another page**, **opens recipe list**, or **opens saved list** changes the current view. Use the displayed Back control to return without losing the retained draft.

## 2. Install and open EOC

### Steam Workshop

Subscribe, let Steam finish downloading the extension, and enable it in X4 if necessary.

### Manual installation

Place the `JK_Station_Manager` folder directly under `X4 Foundations/extensions`. The final path must contain:

`X4 Foundations/extensions/JK_Station_Manager/content.xml`

Do not add another folder layer.

### Open the menu

1. Load a save and allow roughly ten seconds for initialization.
2. Open the normal **Ship Interactions** menu.
3. Select **OPEN EXECUTIVE OPERATIONS CENTER**.

EOC includes its own Dock Interactions access route; a separate UI framework is not required.

---

## 3. HOME: start with the task

![Build 369 Home](images/EOC_BUILD369_HOME.png)

The Home page intentionally avoids a wall of statistics. It provides four direct routes:

- **PLAN MORE PRODUCTION** opens the voluntary production calculator.
- **CHECK RESOURCE SUPPLY** opens the explicit supply-analysis choices.
- **CONSTRUCTION PROGRESS** reviews an existing X4 construction plan.
- **DELIVERIES AND SHIPS** opens logistics coverage and fleet tools.

The **WHAT NEEDS MY ATTENTION?** panel shows retained problems when one exists. “No open problem” means only that this view has no retained problem to present; it does not prove that every station is healthy. Run Supply analysis when you want a fresh resource check.

---

## 4. STATIONS: choose and understand a station

![Build 369 Stations navigator](images/EOC_BUILD369_STATIONS_HOME.png)

The left navigator lists each owned station, its assigned role, and current monitoring state. Select a station by its name, then use the right side for the task you want.

### Station details, reports, and role

![Build 369 station detail](images/EOC_BUILD369_STATION_DETAIL.png)

This view explains:

- the selected station and its persistent EOC role;
- active cases and retained issues;
- the health/trend classification and why EOC selected it;
- status definitions;
- explicit actions to run a fresh empire analysis or generate a station report.

Changing the EOC role changes how EOC interprets the station. It does not rebuild or reconfigure the station.

The four task shortcuts—**PLAN MORE PRODUCTION**, **CHECK RESOURCE SUPPLY**, **CONSTRUCTION PROGRESS**, and **DELIVERIES AND SHIPS**—carry the selected station into the appropriate workflow.

---

## 5. PLANS: model additional production

The Build 369 production calculator answers: “If I want to add this production here, what would the scenario require?” It is separate from evidence-backed repair plans.

![Build 369 Plans home](images/EOC_BUILD369_PLANS_HOME.png)

### Step 1: choose the station

Open the station dropdown on the Plans page and choose the target station.

![Build 369 in-page station selector](images/EOC_BUILD369_PLANS_STATION_SELECTOR.png)

You do not need to return to the Stations tab. Changing stations preserves the reusable draft choices but invalidates a calculated result tied to the previous station. Check the scenario again after switching.

### Step 2: choose an owned production recipe

Select **> NEXT: CHOOSE PRODUCT** or **CHANGE PRODUCT**.

![Build 369 production recipe list](images/EOC_BUILD369_PLANS_PRODUCT_LIST.png)

The recipe catalog is presented in two columns with bounded pages. Choose the exact ware/recipe you want to model. **< BACK TO YOUR PLAN** keeps the previous draft.

### Step 3: choose the target

The target row toggles between:

- **ADD PRODUCTION MODULES** — enter the number of modules to add.
- **UNITS PER HOUR** — enter the additional hourly output to model.

The number field changes meaning with the target. Read the label immediately above it, enter the value, and press **TAB**.

### Step 4: choose how to treat inputs

#### Supply from other stations or trade

![Build 369 external-input assumption](images/EOC_BUILD369_PLANS_EXTERNAL_INPUTS.png)

This assumes you will arrange the required inputs elsewhere. It does not search for sellers, prove availability, or order deliveries.

#### Include supporting production here

![Build 369 supporting-production assumption](images/EOC_BUILD369_PLANS_SUPPORTING_PRODUCTION.png)

This adds dedicated upstream production to the calculation. Existing capacity is not deducted. Mined resources and unsupported recipes still require outside supply.

### Step 5: check the scenario

Select **> NEXT: CHECK SCENARIO**.

![Build 369 scenario result](images/EOC_BUILD369_PLANS_SCENARIO_RESULT.png)

Read every result page. The summary identifies the requested output, installed evidence, required input rates, calculated module rows, workforce information where available, and unresolved boundaries.

The amber warning is important: the result is a **PLAYER SCENARIO, NOT BUILD APPROVAL**. Existing/planned modules are not deducted, and habitat/provisions, storage allocation, delivery throughput, construction materials, placement, and cost remain unverified. Raw resources still require mining or trade. Multi-product recipes remain external dependencies.

### Step 6: save the advisory checklist

After reviewing every page, select **> AFTER REVIEW: SAVE ADVISORY CHECKLIST**.

![Build 369 saved confirmation](images/EOC_BUILD369_PLANS_SAVED_CONFIRMATION.png)

The **SAVED: exact scenario read back** message confirms that EOC persisted the scenario record. It does not mean X4 approved or started construction.

Open **SAVED PLANS** to see retained scenarios.

![Build 369 Saved Plans list](images/EOC_BUILD369_PLANS_SAVED_LIST.png)

Select a saved row to reopen the exact snapshot.

![Build 369 saved-plan detail](images/EOC_BUILD369_PLANS_SAVED_DETAIL.png)

The saved detail is read-only historical advice. Use **< BACK TO YOUR PLAN** to return to the unsaved working draft. To build anything, compare the advice with X4’s native Station Build Plan and add the modules yourself.

### Existing repair plans are different

**RELATED TOOL: EXISTING REPAIR PLANS (opens another page)** leads to EOC’s recovery-gated repair planner and its saved build lists. It is not another step in the voluntary calculator.

---

## 6. CHECK RESOURCE SUPPLY

Supply analysis runs only when you explicitly request it. Opening a Supply view, changing a selector, or paging does not silently scan the empire.

![Build 369 Supply choices](images/EOC_BUILD369_SUPPLY_CHOICES.png)

Choose the question you want answered:

- **WHAT IS MY EMPIRE SHORT OF?** compares installed player-owned capacity with measured internal station demand.
- **WHAT DOES MY SELECTED STATION MAKE AND USE?** shows a station-level supply profile.
- **PLAN MORE PRODUCTION** opens the voluntary calculator.
- **ALL SUPPLY TOOLS: PRICES, STORAGE AND CAPACITY** opens specialist views.

After entering a view, select **RUN THIS ANALYSIS** or **REFRESH THIS ANALYSIS**. Do not repeatedly refresh unless production, demand, storage, or the selected station has changed.

### Read the empire balance

![Build 369 Empire Supply Balance](images/EOC_BUILD369_SUPPLY_BALANCE.png)

- `100%` means measured installed supply equals measured demand.
- Below `100%` means a measured shortage.
- Above `100%` means measured capacity exceeds measured demand.
- `/h` means units per game hour, not stock in storage.
- Red is severe, amber is shortage, green is balanced, and cyan is surplus.

Raw resources such as gases and minerals are labeled as mining/trade sources rather than station-production candidates.

Select a resource card for its explanation and next step.

![Build 369 resource shortage detail](images/EOC_BUILD369_SUPPLY_RESOURCE_DETAIL.png)

The detail states the plain-language result, what the numbers mean, what the snapshot does not prove, and whether evidence supports opening or viewing a case. Creating an investigation is a deliberate player action; selecting a resource alone does not authorize construction, trade, or ship assignment.

---

## 7. HISTORY: read retained reports

![Build 369 History](images/EOC_BUILD369_HISTORY.png)

History lists recent EOC reports and selects the newest completed report automatically. Choose another report to read it. Reports explain the station, health, trend, priority, and current recommendation recorded at that time.

The EOC menu retains a bounded recent list. Permanent copies remain in **Player Information > Logbook > Tips**. Use a report’s Return control when available to continue from its originating workflow.

---

## 8. SETTINGS: define EOC’s authority

![Build 369 Settings](images/EOC_BUILD369_SETTINGS.png)

Opening Settings changes nothing. Read the scope beside every control before changing it.

### Global ship minimums

Set floors for miners, traders, construction-storage traders, defence ships, and escorts. Zero disables that category. Select **SAVE GLOBAL SHIP MINIMUMS** after editing.

EOC fills at most one verified shortage per scan using compatible idle registered ships. It never creates free ships or queues an empire-wide build order.

### Construction funding

- **APPROVAL REQUIRED** waits for confirmation of each exact verified shortfall.
- **DO IT ALL** may fund verified construction and assign eligible idle builders within that authority.

Neither mode creates or changes the station plan.

### Trade order control

- **ADVISOR MODE** provides instructions only.
- **MANAGED TRADE** may create evidence-supported EOC-owned offers.

### Ship assignment authority

- **APPROVAL REQUIRED** waits for player confirmation.
- **AUTO-ASSIGN REGISTERED** may assign only eligible ships already registered with EOC.

Other ship-management or trading mods can compete for the same ships. If assignments repeatedly change, disable one automation system or keep EOC in Approval Required mode.

---

## 9. ALL TOOLS: nothing was removed

![Build 369 All Tools](images/EOC_BUILD369_ALL_TOOLS.png)

All Tools exposes the specialist workflows behind the simplified top navigation:

1. Manage a station
2. Station history and overview
3. Money, storage and other statistics
4. Resource supply analysis
5. Deliveries, assigned ships and ship building
6. Cases and retained evidence
7. Repair planner and saved build lists
8. Construction and funding
9. Reports
10. Permissions and preferences
11. Problem diagnosis and verification

Use **NEXT** for the second page of the list.

---

## 10. DELIVERIES, ASSIGNED SHIPS AND SHIP BUILDING

![Build 369 Fleet and Logistics](images/EOC_BUILD369_FLEET_LOGISTICS.png)

The Fleet & Logistics Center separates station coverage, registered ships, observed trade activity, pending work, and fleet management. Its conclusion tells you whether player approval, an eligible registered ship, or no change is currently required.

Select **FLEET MANAGEMENT** to open saved fleet-production templates.

![Build 369 Fleet Build Manager](images/EOC_BUILD369_FLEET_MANAGER.png)

Saved templates define requested fleets; they do not bypass player-owned blueprints, compatible shipyards, normal resources, preview, or confirmation.

Select **CREATE NEW FLEET TEMPLATE** to name a fleet and add ships from owned blueprints.

![Build 369 new fleet template](images/EOC_BUILD369_FLEET_TEMPLATE.png)

Use the size filters or name search, then select **ADD ONE** beside a blueprint. Review the completed template and the separate preview/confirm steps before issuing an order. Submission is not proof that a ship was built or delivered.

---

## 11. Cases, diagnosis, repair, and construction

These specialist tools remain under **ALL TOOLS**.

### Cases and retained evidence

A case keeps an exact station/subject problem, its evidence, responsibility, and next action together. Open an existing case instead of creating a duplicate. A first Supply snapshot does not prove persistence; EOC requires retained evidence before it can support stronger conclusions.

### Problem diagnosis and verification

Request verification once, follow the displayed inspection or correction, and wait for the retained result. Do not repeat the same request while it is checking or waiting. **UNCHANGED**, **IMPROVING**, **WORSENING**, **BLOCKED**, and **TEST COMPLETE** describe evidence states, not player intent.

### Repair planner and saved build lists

The repair planner is evidence-backed and recovery-gated. Immediate trade, funding, delivery, or assignment options are considered before permanent expansion. Saved repair lists track an agreed response to an exact case; they are separate from voluntary Plans scenarios.

### Construction and funding

Construction reviews an X4 plan that already exists. Refresh it to inspect the queue, builder, required wares, budget, and progress. Funding authority covers only an exact X4-reported shortfall and never creates or edits the plan.

---

## 12. Troubleshooting and support

### The EOC button is missing

1. Confirm EOC is enabled.
2. For manual installs, confirm the extension has no extra folder layer.
3. Load the save, wait about ten seconds, then close and reopen Ship Interactions.
4. If another mod replaces the same menu, test without that mod at your own risk. EOC cannot guarantee compatibility with another mod that replaces its access route.

### A typed number did not change

Press **TAB** or leave the field to commit it, then run the calculation or preview again.

### A Plans result disappeared after switching stations

That is intentional. Calculated results belong to the station used for the calculation. Your reusable draft choices remain, but you must check the scenario again for the newly selected station.

### Get the debug log for a report

After reproducing the problem and exiting X4 normally, locate:

`C:\Users\<Windows user>\Documents\Egosoft\X4\<numeric profile>\debuglog.txt`

Copy `debuglog.txt` before starting X4 again so the evidence is preserved. Upload the copied file to the GitHub issue with:

- EOC build/version and X4 version;
- exact steps, expected result, and observed result;
- affected station, ware, ship, or menu;
- relevant enabled mods;
- display resolution/UI scale for presentation problems;
- a screenshot of the exact EOC page.

Issues: <https://github.com/razoreqx1/JK-Empire-Operations/issues>

An `[=ERROR=]` prefix alone does not prove an EOC failure; some EOC diagnostics use X4’s error channel. Include the complete copied log so the event text and surrounding evidence can be reviewed.

---

## 13. One-page operating rule

**Choose the task → read the conclusion → follow the single NEXT action → commit edited values with TAB → preview any gameplay change → confirm only the exact scope → wait for X4 readback.**

For production scenarios, add one more rule:

**Saved advice is not construction approval. Compare it with X4’s Station Build Plan and build manually.**
