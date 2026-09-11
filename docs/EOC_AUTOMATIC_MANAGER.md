# EOC automatic manager — Build383 companion guide

This is the guide for the optional existing-assets manager in Build383/version483. Game acceptance is still required; it is not a promise that every trade problem can be repaired or that profits will rise.

## Two ways to play

**Assisted EOC stays as it is.** Keep using Home questions, Fix This, station batches, plans, evidence, reports and money comparisons. The new manager starts **OFF** and is separate from the manual shipping setting. Assisted EOC does not require X4 Diagnostics.

**Automatic management is opt-in.** Once enabled, EOC checks your owned stations in the background, investigates persistent shortages and product overages, attempts supported corrections, checks delivery outcomes and revisits unresolved conditions after a cooldown. You do not need to keep EOC open or click through each automatic assessment.

## Turn it on

1. Use Build383 EOC with **X4 Diagnostics B007 or later** and its declared **SirNukes Mod Support APIs (version 1.95 or later)** dependency. Merely having an older Diagnostics version installed is insufficient: the compatible tracking bridge must respond. Do not run duplicate loose and subscribed copies of either mod. Diagnostics does not require a manually started ship recording for this bridge.
2. Open **Home → Can EOC manage my existing stations and ships automatically?**, or **Settings → Optional Automatic Manager – Existing Assets**.
3. Select **Refresh Status**. Set the three credit limits and select **Save Limits**. Read the saved values shown above the edit fields.
4. Select **Enable Automatic Management…**, then **Confirm: Enable Automatic Management**.
5. Close EOC and continue playing. Simulation time must advance. You may revisit the page and select **Refresh Status** for its latest retained state.

Missing or incompatible tracking prevents activation. Losing responsive tracking after activation pauses new dependent actions; existing orders are preserved. EOC retries dependency checks on its bounded background cadence.

## What it may do

- Investigate owned-station input shortages and output overages across a rotating station list, using separated stock readings rather than treating every dip as a fault.
- Use compatible ships already assigned to the station, registered idle ships, and eligible previously EOC-assigned donors where the existing donor checks permit it.
- Arrange supported native purchase/delivery orders or verify an exact mining assignment, subject to current ownership, role, orders, cargo, range, docking and trade restrictions.
- Prefer a recently successful trade partner when current offers and all safety checks still permit the route.
- Preserve ongoing work, retain outcomes and retry unresolved conditions after a bounded wait.

It does **not** buy ships, build modules, grant cargo or credits, transfer account funding, rewrite public trade offers, override blacklists, seize busy ships or guarantee profitable operation. A station with no usable offers or no eligible ship may still need a player decision. Unregistered idle ships are not automatically enrolled. Existing open manual recovery work is preserved and blocks a duplicate automatic job for that station/ware; enabling automation does not silently take over those manual records.

## Credit limits

| Setting | Default | Meaning |
|---|---:|---|
| Per order | 500,000 Cr | Maximum conservative purchase quote for one EOC automatic shipment; quantities may be reduced while respecting native minimum lots. |
| Per hour | 5,000,000 Cr | Rolling simulation-hour ceiling across automatic purchase reservations. |
| Station reserve | 1,000,000 Cr | Credits EOC requires to remain in the station account after its outstanding reservations. |

Pending reservations continue counting even after an hour. Once their native orders end, the quoted amount is conservatively retained for the applicable rolling window; EOC does not invent refunds or count a quote as profit. Other game activity can still spend station funds. These controls limit this manager's orders, not every account transaction in the empire. If the remaining allowance cannot fund the selected shipment, EOC pauses that attempt rather than bypassing the limit.

## What EOC learns

It retains **confirmed transferred units for exact station, ware, direction and trade partner**. Repeated callbacks for the same deal do not count the same units twice. Recent delivery evidence influences which currently available partner is tried first; every new attempt still checks today's conditions. Partner relevance lasts six simulation hours and memory is bounded to 128 entries.

This is retained evidence and route preference, not a self-training AI or a forecast of guaranteed profit. Docking, movement, a stock increase, an accepted order or a player checkmark alone is not proof of successful delivery. Diagnostics supplies fresh owned-ship/order/location observations; native trade-deal readback supplies delivery evidence.

## Progress, reports and stopping

**Automatic Manager** shows the current status, active-job count, learned-partner count and latest outcome. Full automatic reports are in **Logbook → Tips**. The manager keeps 64 recent outcome snapshots separately from manual report retention. Finished idle automatic jobs retire only after pending/native work and reservation checks allow it; this is separate from the manual Reviewed / Archive action.

Select **Stop New Automatic Actions** whenever you want to stop. It prevents new automatic mutations and preserves saved evidence, reserved quotes, existing native orders and their reconciliation. It does not cancel a shipment you already paid for. A paid-cargo job may remain pending if completing it would require a new order while automation is off. Manual EOC controls remain separate.

Saved opt-in and limits persist. Reloading uses a new worker generation and reacquires tracking; old callbacks cannot create a duplicate manager chain. Actual save/load behavior is a required in-game acceptance check.

## Why it may take time

The controller advances every 30 simulation seconds, checks at most 16 ware slots per pass and refreshes the owned-station list at most once per ten minutes. A large empire takes several passes; this is deliberately not an every-frame galaxy scan. A candidate needs separated observations at least two minutes apart. At most 16 automatic routes are retained concurrently and four shared investigations run at once.

Unresolved completed attempts wait about 30 minutes before another attempt; resolved/no-current-failure routes use a ten-minute cooldown. Existing orders may take longer and remain preserved. Capacity reached means **coverage is incomplete**, not that all other stations are healthy. Optional observer subscriptions expire after 180 seconds without renewal.

## Logic illustration

The retained [autonomy concept animation](eoc-autonomy-logic.gif) is under 2 MB. It illustrates the intended diagnose → act → verify → remember loop, not a live recording. Its original **proposed** label is deliberately preserved until in-game acceptance; this guide's scope and limitations control what Build383 actually implements.

## Before considering this build accepted

Check activation with and without compatible B007 tracking; one real trade's payment and transfer; stopping before dispatch and during paid delivery; save/reload without duplicate purchases; manual EOC unchanged; exact mining readback if exercised; and background performance on your empire. All X4-dependent behavior remains **RUNTIME ACCEPTANCE REQUIRED** until those observations are recorded against the exact build.
