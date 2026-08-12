# JK Empire Operations Center (EOC)

A governance-first operations layer for X4: Foundations.

## Current release

- Version: 2.4 GA
- Release build: 169
- X4 compatibility: 8.x / 9.x
- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957

## What is new in EOC 2.4

- Guided Recovery separates the first blocker, supporting evidence, the next player action, and fresh verification.
- Stable case provenance binds a diagnostic directly to its original station and ware.
- Players can preview and confirm one bounded NPC-enabled BUY or SELL test without changing existing ware rules or ordinary offers.
- EOC removes only its matching test offer and blocks repeat creation or completed-removal submissions.
- Pending confirmations use a consistent amber state across market, fleet, ship-order, role, and policy controls.
- To make a successful market path permanent, change only that ware's buy or sell trade rule in the station Logical Overview. EOC never converts a test into permanent policy automatically.

## Existing EOC capabilities

- Full EOC management window from **Dock Interactions > OPEN EXECUTIVE OPERATIONS CENTER**.
- Separate EOC pinwheel navigation; EOC does not register or intercept Ctrl+H.
- Named fleet-production templates with partial, case-insensitive blueprint search.
- One-yard or distributed owned-shipyard planning with separate Preview and Confirm actions.
- Owned blueprints, X4-generated loadouts, normal shipyard resources, native captains and crew, and duplicate-order protection.

## First-time access

1. Load the game and wait about 10 seconds for EOC initialization.
2. Open **Dock Interactions** using the icon immediately to the right of Diplomacy.
3. Select **OPEN EXECUTIVE OPERATIONS CENTER**.
4. On the first EOC use for that save, choose a name for the command intelligence.

## Documentation

- [EOC 2.4 GA User Guide](docs/EOC_2.4_GA_USER_GUIDE.md)
- [EOC 2.4 GA Release Notes](docs/RELEASE_NOTES_2.4_GA.md)

Older release documents remain available in `docs/`.

## Installation

Copy `JK_Station_Manager` into the X4 `extensions` directory, or subscribe through Steam Workshop. Do not add another folder between `extensions` and `JK_Station_Manager`.

## Source and license

The source is provided openly in this repository. See [LICENSE](LICENSE) for the applicable terms.

If EOC has earned it, please consider marking it as a Workshop Favorite.
