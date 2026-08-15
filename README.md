# JK Empire Operations Center (EOC)

Transform your X4 empire from reactive management into intelligent operations.

## Current release

- Version: 3.1 GA
- Engineering build: 218
- X4 compatibility: 8.x / 9.x
- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957

## What is new in EOC 3.1

- Preserves the validated event-driven Dock Interactions access path.
- Adds bounded support tracing for callback registration, button rendering, player selection, and EOC open-event receipt.
- Keeps startup registration bounded and stops immediately after success; no recurring watchdog was added.
- Makes no automation, trade, shipping, construction, KPI, save-data, or player-authority behavior change.
- Retains all EOC 3.0 GA live KPI safeguards, filters, drilldowns, trends, and scroll preservation.

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

- [EOC 3.1 GA User and Support Guide](docs/EOC_3.1_GA_USER_SUPPORT_GUIDE.md)
- [EOC 3.1 GA Release Notes](docs/RELEASE_NOTES_3.1_GA.md)

Older release documents remain available in `docs/`.

## Installation

Copy `JK_Station_Manager` into the X4 `extensions` directory, or subscribe through Steam Workshop. Do not add another folder between `extensions` and `JK_Station_Manager`.

EOC is designed not to make a save dependent on the mod. It adds no permanent custom ships, stations, wares, sectors, or other assets required for the save to load. Players do not need to uninstall EOC before updating, and removing it later does not corrupt the save.

## Source and license

The source is provided openly in this repository. See [LICENSE](LICENSE) for the applicable terms.

If EOC has earned it, please consider marking it as a Workshop Favorite.
