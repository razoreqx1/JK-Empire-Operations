# EOC - Executive Operations Center

![EOC - Executive Operations Center](docs/images/EOC_Workshop_Banner.jpg)

EOC is an intelligent empire-management advisor for **X4: Foundations**. It observes player stations, develops evidence across repeated observations, diagnoses operational problems, recommends corrective action, teaches the player how to respond, and can perform selected actions only under player-controlled authorization modes.

## Current release

**Version 1.0 GA**  
**Supported game version:** X4: Foundations 9.0 or newer  
**Author:** RazorEQX  
**Steam Workshop:** [EOC - Executive Operations Center](https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957)

> X4 8.0 is not supported by the current GA release. Two Mission Director constants used by EOC were introduced in X4 9.0; on 8.0, the central station manager may fail to initialize and display null values.

## What EOC does

- Monitors player stations and preserves long-term station intelligence.
- Lets the player classify every station by operational role.
- Identifies critical cases, warnings, and stations requiring action.
- Produces empire, station, and operational-remediation reports in the X4 Tips log.
- Diagnoses repeated shortages, overflow, workforce problems, station-health decline, logistics gaps, and related blockers.
- Generates evidence-based recommendations instead of reacting to a single snapshot.
- Can manage supported buy and sell offers when the player enables managed trade orders.
- Can recommend station ship assignments and operate in disabled, approval-required, or registered-ship auto-assignment modes.
- Provides ticker feedback for analysis, reports, changes, assignments, and verification.

## Player control and safety

EOC separates advice from execution.

- **Instructions only:** EOC diagnoses and explains without changing the game state.
- **Approval required:** EOC shows the exact ship, station, and role before assignment.
- **Auto-assign registered ships:** EOC may use only registered, supported candidates for verified station needs.
- **Managed trade orders:** A separate opt-in control that can be disabled later.

EOC does not buy ships, blueprints, variants, or equipment. It does not intentionally take drones, units, XS craft, the player's current ship, mission-controlled ships, already assigned ships, or unsupported candidates.

## Installation

### Steam Workshop

1. Subscribe on the [Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957).
2. Allow Steam to download the item.
3. Start X4 and confirm EOC is enabled under Extensions.
4. Load a save and confirm the EOC startup entry in **Player Information > Logbook > Ticker**.

### Manual installation

1. Download or clone this repository.
2. Copy `JK_Station_Manager` into the X4 `extensions` directory.
3. Ensure `content.xml` is directly inside `extensions/JK_Station_Manager`.
4. Restart X4 and enable the extension.

## First-time setup

1. Load the game and confirm the EOC 1.0 GA startup ticker entry.
2. Open **Extension Options > EOC**.
3. Open **Executive Advisor**.
4. Choose **Station Role Assignment** and classify every player station.
5. Run **Analyze Now** and wait for the completion ticker entry.
6. Generate the **Empire Executive Report** and read it under **Player Information > Logbook > Tips**.
7. Review Critical cases first, followed by Warnings and Stations Requiring Action.
8. Leave automation disabled until the reports and recommendations make sense to you, then enable one managed capability at a time.

## User manual

The illustrated 15-page manual covers installation, every primary menu, station roles, analysis, reports, remediation, managed trade orders, shipping-control modes, ship assignment, verification, and troubleshooting.

**[Download the EOC 1.0 GA New User Guide (PDF)](docs/EOC_1.0_GA_New_User_Guide.pdf)**

## Repository layout

- `JK_Station_Manager/` - clean runtime extension files required by X4.
- `docs/EOC_1.0_GA_New_User_Guide.pdf` - illustrated user manual.
- `docs/RELEASE_NOTES_1.0_GA.md` - GA release summary and known limitations.
- `docs/images/` - public documentation artwork.

Internal test plans, debug snapshots, engineering handoffs, and development archives are intentionally excluded from the public GA repository.

## Reporting a problem

When reporting an EOC issue, include:

- X4 version and hotfix number.
- EOC version shown in the startup ticker.
- The exact menu action or game event that preceded the issue.
- A screenshot of the player-facing result.
- The relevant X4 debug log when available.

Please separate EOC errors from unrelated third-party mod errors whenever possible.

## License

This repository is licensed under the [MIT License](LICENSE).

