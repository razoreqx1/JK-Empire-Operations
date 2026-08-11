# EOC 2.1 GA User Guide

## Purpose

The Executive Operations Center is a player-directed operations layer for X4: Foundations. It reports what needs attention and performs only the actions the player explicitly approves.

## Open EOC and choose a station

1. Open the EOC menu.
2. Use **Stations** to select the station you want to review.
3. Open **Fleet & Logistics** for logistics status and actions.
4. Read the **EOC Conclusion** and **Do This Next** guidance before acting.

## Check whether a station needs a ship

1. In **Fleet & Logistics**, select **Does a station need a ship?**
2. EOC checks supported logistics needs and compatible registered ships.
3. A ship-order recommendation appears only when EOC finds a supported shortage and no compatible logistics ship is available.

The current ship-order workflow supports container, solid, and liquid logistics requirements.

## Choose Medium or Large

When EOC can verify both a Medium and a Large option, it shows two deliberate choices:

- **Choose: Medium**
- **Choose: Large**

Each option must use a blueprint the player owns and a compatible player-owned shipyard that can build that hull. If only one size is valid and buildable, EOC offers only that size. If neither is valid, EOC reports the missing blueprint or compatible shipyard and submits nothing.

Choosing a size does not queue a ship.

## Preview the order

After choosing a size, select **Preview EOC Order**. The preview shows the exact hull and build location EOC intends to use.

Preview is informational and does not queue a ship.

If the shipyard or blueprint is no longer valid, EOC cancels the preview and submits nothing.

## Confirm exactly one ship

After reviewing the preview, select **Confirm: Queue Exactly 1 Ship**.

Only this confirmation submits the order. EOC then:

- asks X4 for a valid generated loadout;
- submits one native build task to the compatible player-owned shipyard;
- lets the shipyard consume normal hull and equipment resources;
- relies on X4's normal captain and crew lifecycle;
- locks duplicate submission for the same station, cargo need, and hull requirement.

EOC never creates a free ship, bypasses resources, opens the vanilla ship-configuration screen, repeats an order, or enables automatic ship production.

## After submission

A successful order reports that X4 accepted the native task. No further EOC click is required while the player-owned shipyard handles resource delivery, queueing, and construction.

After the ship is complete:

1. Return to **Fleet & Logistics**.
2. Select **Register Suitable Unassigned Ships**.
3. Assign the ship to the station as appropriate.
4. Run **Scan Shipping Needs** again before considering another order.

## Duplicate protection

Once an order is accepted, EOC blocks another order for the same station and logistics need. The lock applies across Medium and Large choices, so changing size cannot create a duplicate.

## Other Fleet & Logistics actions

- **Register Suitable Unassigned Ships** finds eligible unassigned trade and mining ships.
- **Scan Shipping Needs** reviews supported station needs against eligible registered ships.
- **Review EOC Trade Orders** checks only EOC-owned trade offers and reports changes.
- **Pending** shows work waiting for player approval when approval-required operation is enabled.

## Troubleshooting

### No ship option appears

Check that:

- the station has a supported logistics shortage;
- no compatible registered ship already satisfies it;
- the player owns a suitable blueprint;
- a compatible player-owned shipyard is operational for that hull size.

### The order is waiting

The player-owned shipyard may be waiting for normal construction resources or an available build module. EOC does not bypass either condition.

### The interface says accepted and verifying

Do not confirm again. Duplicate submission is already locked while EOC waits for the native X4 task to appear.

### The task is accepted

No more EOC action is required until construction finishes.

## Safety boundaries

EOC is deliberately player-controlled:

- size choice, preview, and confirmation are separate actions;
- exactly one ship is submitted per confirmed recommendation;
- only owned blueprints and player-owned compatible shipyards are used;
- resources, loadouts, crew, and construction scheduling remain native X4 behavior;
- duplicate orders and automatic production remain disabled.