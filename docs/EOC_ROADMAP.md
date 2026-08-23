# EOC Development Roadmap — The Next Round

With EOC 3.5 GA released, the next development cycle will focus on completing the larger logistics ecosystem.

The long-term goal is simple:

> EOC should manage everything within the authority granted by the player and involve the player only when a genuine construction decision, missing capability, or unavailable resource requires attention.

This roadmap is an approved development direction, not authorization for a new build. Every implementation, package, installation, test, promotion, and publication stage remains separately governed.

## Phase 1 — EOC 3.6 Unified Logistics Coverage

EOC will develop a shared logistics model covering:

- Raw-resource miners
- Station input traders
- Product-selling traders
- Build-storage traders
- EOC-managed emergency BUY and SELL actions

For every station and resource, EOC should clearly report:

- Current stock and target
- Consumption or production rate
- Ships assigned to that resource
- Ships actively working, waiting, blocked, or awaiting their first delivery
- Whether current ship coverage is sufficient
- Whether another ship is genuinely needed
- Whether a valid source is available
- The last confirmed delivery or stock increase

Expected statuses include:

- `COVERED — 2 SHIPS WORKING`
- `AWAITING FIRST DELIVERY`
- `MORE CAPACITY NEEDED — ADD 1 SHIP`
- `SOURCE TEMPORARILY UNAVAILABLE`
- `NO ELIGIBLE SHIP AVAILABLE`
- `PLAYER CONSTRUCTION REQUIRED`

The goal is to let players see that “Do Everything” is actually doing everything—not simply assume automation is working in the background.

## Phase 2 — Predictive Intelligence

Once logistics coverage is trustworthy, EOC can begin predicting:

- Approaching resource shortages
- Likely production stalls
- Sustained overstock
- Insufficient selling capacity
- Workforce-supply collapse
- Shared-storage congestion
- Underused miners and traders
- Profit leakage from idle production or missed sales

Every prediction must include supporting evidence and confidence. If EOC cannot prove something, it must report it as unknown rather than guess.

## Phase 3 — Fleet Staffing and Procurement

EOC will expand its fleet-management policies to cover:

- Miners
- Traders
- Build-storage traders
- Defence ships
- Escorts

All global minimums will default to zero.

EOC must count existing suitable ships first, use compatible idle registered ships when authorized, and add capacity gradually. It must never flood shipyard queues, create free ships, steal assigned ships, or bypass normal resources and construction.

When a ship is required but unavailable, EOC should explain exactly what ship type and cargo class the player needs.

## Phase 4 — Only Involve the Player When Necessary

EOC should handle ordinary logistics and economic recovery within player-approved authority. The player should receive a concise persistent notification only when EOC encounters something it cannot safely resolve, such as:

- Production or storage modules that must be built
- Missing blueprints
- No compatible shipyard or ship design
- Insufficient construction resources
- No discoverable mining source
- An action exceeding configured authority or credit limits
- Evidence EOC cannot verify safely

The same unresolved issue should not generate repeated alerts every refresh. EOC should maintain one case and update its evidence.

## Phase 5 — Shipyard Supply Planner

A later phase will extend the same evidence-based model to shipyards and wharves.

Planned goals include:

- Analyze complete shipbuilding resource requirements
- Distinguish trader shortages from production shortages
- Identify missing supporting production chains
- Recommend supporting stations and modules
- Track whether completed construction improves ship output
- Preserve the vanilla Station Build Plan and player construction authority

## Permanent Engineering Requirements

Every phase must preserve EOC’s existing safety and performance rules:

- Slow, staggered, bounded manager cycles
- Strict work limits per cycle
- No per-frame analysis
- No duplicate schedulers
- No hidden background Supply scans
- Persistent evidence instead of repeated full scans
- Exact ship, station, and ware identities
- Visible feedback for every player action
- No free ships
- No stealing assigned ships
- No hidden resource creation
- No unauthorized cargo or credit movement
- No automatic station construction
- No unsupported success claims

Community feedback is welcome, especially regarding which logistics information would be most useful at a glance and which situations should require direct player involvement.
