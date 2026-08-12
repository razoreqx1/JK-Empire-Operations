# JK Empire Operations Center (EOC)

A governance-first operations layer for X4: Foundations.

## Current release

- Version: 2.3 GA
- Release build: 157
- X4 compatibility: 8.x / 9.x
- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957

## What is new in EOC 2.3

- Color-coded evidence makes the diagnosis readable at a glance: **green PASS**, **red FAIL**, **amber UNKNOWN**, and **gray neutral/not applicable**.
- A plain-language **BIG TAKEAWAY** identifies the immediate blocker instead of burying it in supporting data.
- Players name their EOC command intelligence on first use; the identity persists and can be changed in Global Settings.
- Conversational Guided Recovery presents one unresolved check, one player action, and then verification.
- Fresh verification truthfully reports **RESOLVED**, **IMPROVING**, **UNCHANGED**, or **WORSENING**.
- Storage-pressure cases show exact free-space failures without irrelevant funds. Relevant funds are labeled **Station Operating Account**.
- The first EOC opening of each X4 session shows five unique humorous startup checks selected from a pool of 30.
- The Stations page now color-codes role and operational status, clearly separates persistent station roles from advisory policies, and distinguishes current, available, and pending-confirmation controls.

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

- [EOC 2.3 GA User Guide](docs/EOC_2.3_GA_USER_GUIDE.md)
- [EOC 2.3 GA Release Notes](docs/RELEASE_NOTES_2.3_GA.md)

Older release documents remain available in `docs/`.

## Installation

Copy `JK_Station_Manager` into the X4 `extensions` directory, or subscribe through Steam Workshop. Do not add another folder between `extensions` and `JK_Station_Manager`.

## Source and license

The source is provided openly in this repository. See [LICENSE](LICENSE) for the applicable terms.

If EOC has earned it, please consider marking it as a Workshop Favorite.
