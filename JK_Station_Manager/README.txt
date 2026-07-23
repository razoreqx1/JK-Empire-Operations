JK Empire Operations v2.0.0 - Investigation Engine Alpha
Author: RazorEQX

This release is the first evidence-driven investigation build. It remains
advisory-only: it changes no ships, station logic, storage allocation, trade
rules, build plans, or wares.

New in v2.0.0:
- Persistent shortage investigation stages: DETECTED, OBSERVING, PERSISTENT, DIAGNOSING
- Persistence triggers investigation instead of automatically recommending deliveries
- Recommendation text escalates from Observe to Investigate
- Rich shortage summary and evidence pages
- Separates confirmed facts from causes that have not yet been proven
- Captures allocation, target, station ship count, storage-module count and funds
- Root-cause confidence remains INSUFFICIENT EVIDENCE until future analyzers prove a cause
- Detailed V200 investigation logging

Design rule: the advisor must never guess. It observes, gathers evidence,
explains what is known, and waits when a cause cannot yet be proven.

Open Empire Operations with Ctrl+H. Refresh Analysis performs an immediate scan.
See V2.0.0_TEST_PLAN.txt for one-test-at-a-time validation.

The extension ID remains jk_station_manager and save="0" remains unchanged.
Removing the extension does not make saves dependent on it.
