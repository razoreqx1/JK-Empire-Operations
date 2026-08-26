# EOC 3.8 GA — Build 324

EOC 3.8 makes the operations center understandable without requiring players to learn EOC's internal shorthand first.

## Highlights

- Supply pages explain the verdict in plain English and define `/h` as units per game hour.
- Coverage explains that `100%` means measured supply equals measured demand, below 100% is a shortage, and above 100% is surplus capacity—not a quality score.
- Supply evidence distinguishes rates from stored inventory and states when ship, route, buyer, price, or trade-permission evidence is not measured by the current snapshot.
- Price and storage proposals explain why EOC made the recommendation and what accepting it changes.
- Cases lead with who is responsible, what is happening now, and the next action; detailed evidence remains available below.
- Existing player investigations route directly to their Case instead of offering a duplicate request button.
- Storage is ranked highest-first with thresholds, exact fill, change from the prior sample, and a capacity bar.
- Executive Attention replaces raw internal scores with understandable state, issue count, and reasons.
- KPI percentages identify their baseline, and Cash Flow can retain up to one hour of on-screen history.
- The accepted `WAITING FOR TRADE CYCLE` state and all EOC 3.7 Predictive, Case, recovery, and return-path behavior remain intact.

## Authority boundaries

Supply analysis remains explicit and on demand. Build 324 adds no watcher, polling loop, per-frame analysis, recurring Supply scan, free ship, unauthorized construction, cargo movement, credit movement, or resource creation.

Build 324 is the identity-only GA promotion of the human-accepted Build 323 runtime.
