# JK Empire Operations Center (EOC)

Transform your X4 empire from reactive management into intelligent operations.

## Current public test

- Version: 3.5 TEST
- Engineering build: 286
- Status: **WORK IN PROGRESS PUBLIC TEST** — the Supply Model and native Station Solution Planner are under active testing
- X4 compatibility: 8.x / 9.x
- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957

Build 259 remains the last GA-qualified runtime. Build 286 is available for public testing on Steam and GitHub.

## What is new in EOC 3.5 TEST Build 286

- Adds a native Station Solution Planner that uses X4's owned-blueprint and library data for the exact module, blueprint ware, production method, cycle output, complete primary-input recipe, workforce, and storage classes.
- Calculates recommended additional modules as the live non-negative hourly deficit divided by exact one-module hourly output, rounded up.
- Keeps permanent planning locked behind explicit recovery-exhaustion and expansion-readiness evidence.
- Adds selected-station Supply navigation, persistent two-snapshot Supply-to-Case handling, centralized duplicate-case prevention, and selected-station batch price confirmation with immediate read-back.
- Uses bounded native scrolling across EOC pages and preserves the same-page top and selected row.
- Keeps Supply analysis player-triggered: no Supply watcher, polling loop, per-frame analysis, or recurring Supply scan.
- Does not add modules, place plots, alter build plans, create resources, or move cargo or credits.
- Continues to exclude Raw Scrap from conventional Supply recommendations.

Build 286 passed its targeted live test at 3840x2160 with X4 UI scale 2.00. The complete planner rendered with native scrolling, and the fresh log contained no EOC widget-height rejection, Lua error, Mission Director failure, stack trace, or invalid argument in the tested workflow. This is still a public TEST across wider resolutions, UI scales, saves, and mod combinations.

## Preserved EOC 3.2 foundation

- Makes Dock Interactions access self-contained within EOC, so a separate UI framework installation is not required for the EOC button.
- Packages the Docked-menu integration through X4's native substitution catalog and safely preserves compatible callbacks when another UI addon loaded first.
- Uses EOC-owned fallback colors throughout the interface so every tab renders with or without optional shared UI helpers.
- Remains compatible with UI Extensions and HUD when players keep it installed for other mods.
- Adds high-level Lua docblocks, Mission Director subsystem headers, and a developer architecture guide covering ownership, persistent schemas, authority boundaries, and invariants.

Build 259 also preserves the complete EOC 3.2 feature set:

- Adds bounded managed BUY actions for confirmed shortages and SELL actions for storage pressure.
- Adds Scout's long-term recommendations and ordered recovery playbooks across every supported issue family.
- Adds persistent two-way EOC/player command checklists with EOC-owned evidence, player decisions, and automatic verification.
- Preserves managed-action baselines so later stock movement can resolve, improve, or escalate a case.
- Makes Clear All reset cases, evidence, managed trade actions, checklist answers, and command requests before one fresh analysis.
- Isolates Docked-menu callbacks so one failing UI addon callback cannot suppress EOC access.
- Adds bounded Dock lifecycle diagnostics without a watcher, polling loop, or per-frame repair.
- Clarifies empire-analysis scope, storage evidence, and transient case-result ownership.
- Same-page buttons, forced verification, and automatic refreshes preserve the player's visible scroll position.
- Excludes Raw Scrap from conventional shortage cases, managed BUY actions, supplier/local-production advice, and EOC checklists because native X4 treats it as an infinite sink.
- Retires prior Raw Scrap EOC state through one bounded cleanup while preserving player-created investigations and continuing to monitor recycling stations and every other ware.
- Removes the obsolete EOC conversation pinwheel. Dock Interactions is now the authoritative access path, and closing EOC returns directly to normal play.

## Existing EOC capabilities

- Self-contained access from **Dock Interactions > OPEN EXECUTIVE OPERATIONS CENTER**.
- Persistent station roles and role-aware operational recommendations.
- Guided Recovery, evidence-backed cases, verification, bounded market tests, Managed Trade, shipping control, fleet templates, and reports.
- Mission-aware analysis, including intentional Terraforming-related activity.
- Player-controlled authority modes, deliberate amber confirmations, duplicate prevention, and no free ships or resource bypass.

## First-time access

1. Load the game and wait approximately 10 seconds for EOC initialization.
2. Open **Dock Interactions** from the top HUD menu.
3. Select **OPEN EXECUTIVE OPERATIONS CENTER**.
4. On first use, choose a name for the command intelligence.

## Documentation and support

- [EOC 3.5 TEST Public Test Guide](docs/EOC_3.5_TEST_PUBLIC_TEST_GUIDE.md)
- [EOC 3.2 GA User and Support Guide](docs/EOC_3.2_GA_USER_SUPPORT_GUIDE.md)
- [EOC 3.2 GA Release Notes](docs/RELEASE_NOTES_3.2_GA.md)
- [Report an EOC issue](https://github.com/razoreqx1/JK-Empire-Operations/issues)

Older release documents remain available in `docs/`.

## Installation

Copy `JK_Station_Manager` into the X4 `extensions` directory or subscribe through Steam Workshop. Do not add another folder between `extensions` and `JK_Station_Manager`. No separate UI framework is required for EOC; optional UI mods may remain installed for other extensions.

EOC is designed not to make a save dependent on the mod. It adds no permanent custom ships, stations, wares, sectors, or other assets required for the save to load. Players do not need to uninstall EOC before updating, and removing it later does not corrupt the save.

## Source and license

The source is provided openly in this repository. See [LICENSE](LICENSE) for the applicable terms.

If EOC has earned it, please consider marking it as a Workshop Favorite.
