# JK Empire Operations Center (EOC)

Transform your X4 empire from reactive management into intelligent operations.

## Current release

- Version: 3.2 GA
- Engineering build: 239
- X4 compatibility: 8.x / 9.x
- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957

## What is new in EOC 3.2

- Adds native Player Wealth, Case Trends, and Empire Growth graphs with 5, 10, and 30-minute ranges.
- Redesigns KPI detail views as bounded five-row pages covering cash flow, profit, construction, shortages, attention, trade, logistics, storage, workforce, shipyards, earners, and drains.
- Reports actual shipyard ship workload without counting station-module construction as ships.
- Reduces shipyard polling to five minutes and construction/remediation matching to two minutes.
- Shows compatible available player ships without silently registering or controlling them.
- Adds zero-default global minimum policies for mining, trade, build-storage trade, defence, and escorts.
- Adds two-step Clear All EOC Cases with an immediate MONITORING / STABLE reset and one fresh analysis.
- Requires visible supporting cases or retained evidence for non-healthy station classifications.
- Improves player-case evidence handoff and terminal no-match diagnostics.

## Existing EOC capabilities

- Standalone EOC access from **Dock Interactions > OPEN EXECUTIVE OPERATIONS CENTER**, plus the EOC pinwheel.
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

- [EOC 3.2 GA User and Support Guide](docs/EOC_3.2_GA_USER_SUPPORT_GUIDE.md)
- [EOC 3.2 GA Release Notes](docs/RELEASE_NOTES_3.2_GA.md)

Older release documents remain available in `docs/`.

## Installation

Copy `JK_Station_Manager` into the X4 `extensions` directory, or subscribe through Steam Workshop. Do not add another folder between `extensions` and `JK_Station_Manager`.

EOC is designed not to make a save dependent on the mod. It adds no permanent custom ships, stations, wares, sectors, or other assets required for the save to load. Players do not need to uninstall EOC before updating, and removing it later does not corrupt the save.

## Source and license

The source is provided openly in this repository. See [LICENSE](LICENSE) for the applicable terms.

If EOC has earned it, please consider marking it as a Workshop Favorite.
