# JK Empire Operations Center (EOC)

A governance-first operations layer for X4: Foundations.

## Current release

- Version: 2.8 GA
- Release build: 199
- X4 compatibility: 8.x / 9.x
- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957

## What is new in EOC 2.8

- Reassigns an eligible player construction vessel from another role and targets it to the selected station's exact build request through X4's native construction workflow.
- Verifies the exact vessel is attached before reporting success. Live testing confirmed the reassigned Elephant actively advanced station construction.
- Adds an explicit **SAVE GLOBAL SETTINGS** workflow with amber unsaved state and green saved confirmation.
- Makes the optional computer loading-screen preference persist per save. It remains ON by default until the player explicitly turns it off and saves the setting.

## Existing EOC capabilities

- Standalone EOC access from **Dock Interactions > OPEN EXECUTIVE OPERATIONS CENTER**; UI Extensions and HUD is not required.
- Station construction status, ordered module progress, missing build wares, exact verified funding, builder assignment, and build-storage evidence.
- Guided Recovery, evidence-backed cases, verification, bounded market tests, Managed Trade, shipping control, fleet templates, and reports.
- Player-controlled authority modes, deliberate amber confirmations, duplicate prevention, and no free ships or resource bypass.

## First-time access

1. Load the game and wait about 10 seconds for EOC initialization.
2. Open **Dock Interactions** from the top HUD menu.
3. Select **OPEN EXECUTIVE OPERATIONS CENTER**.
4. On first use, choose a name for the command intelligence.

## Documentation and support

- [EOC 2.8 GA User and Support Guide](docs/EOC_2.8_GA_USER_SUPPORT_GUIDE.md)
- [EOC 2.8 GA Release Notes](docs/RELEASE_NOTES_2.8_GA.md)

Older release documents remain available in `docs/`.

## Installation

Copy `JK_Station_Manager` into the X4 `extensions` directory, or subscribe through Steam Workshop. Do not add another folder between `extensions` and `JK_Station_Manager`.

EOC is designed not to make a save dependent on the mod. It adds no permanent custom ships, stations, wares, sectors, or other assets required for the save to load. Players do not need to uninstall EOC before updating, and removing it later does not corrupt the save.

## Source and license

The source is provided openly in this repository. See [LICENSE](LICENSE) for the applicable terms.

If EOC has earned it, please consider marking it as a Workshop Favorite.