# EOC - Executive Operations Center

![EOC - Executive Operations Center](docs/images/EOC_Workshop_Banner.jpg)

EOC is an intelligent empire-management advisor for **X4: Foundations**. It observes player stations, builds evidence across repeated observations, diagnoses operational problems, recommends corrective action, teaches the player how to respond, and performs selected actions only under player-controlled authorization modes.

## Current release

**Version 1.8 GA**

**Supported game versions:** X4: Foundations 8.0 and 9.0

**Author:** RazorEQX

**Steam Workshop:** [EOC - Executive Operations Center](https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957)

> After loading a save, wait approximately **10 seconds** for EOC to initialize. Open EOC anywhere with **Control + H**, or from **Dock Interactions** while seated in the Personal Office.

## What EOC does

- Monitors player stations and preserves long-term station intelligence.
- Lets the player classify every station by operational role.
- Provides an Executive Intelligence Overview with empire health, operational KPIs, trends, and change summaries.
- Provides a native-style Management Window with Stations, Overview, Fleet & Logistics, Diagnostics, Cases, Reports, and Global Settings.
- Diagnoses shortages, overflow, workforce problems, station-health decline, logistics gaps, supplier problems, and related blockers.
- Generates evidence-based recommendations instead of reacting to a single snapshot.
- Registers eligible unassigned mining and trade ships without taking unsupported or player-controlled ships.
- Scans station shipping needs and either creates a clearly identified pending approval or assigns an eligible registered ship, depending on player authority.
- Can manage supported buy and sell offers when the player enables Managed Trade.
- Preserves page, filter, selection, and return-path state during guided navigation.
- Shows action status, completion feedback, and a clear **NEXT STEP** after operational actions.
- Keeps a completed assignment message visible after the final Pending row is removed.
- Prevents rapid action-button repetition while an operation is processing.
- Adds **OPEN EXECUTIVE OPERATIONS CENTER** to Dock Interactions while seated in the Personal Office.
- Provides a read-only Empire KPI Center with ranked station attention, trends, and operational measures.

## Player control and safety

- **Advisor Mode:** EOC diagnoses and explains without changing trade orders.
- **Managed Trade:** EOC may create evidence-supported EOC trade offers.
- **Ship Assignment Disabled:** EOC does not assign ships.
- **Approval Required:** EOC shows the exact ship, station, and reason before assignment.
- **Auto-Assign Registered:** EOC may assign only eligible registered ships to verified needs.

EOC does not buy ships, blueprints, variants, or equipment. It does not intentionally take drones, units, XS craft, the player's current ship, mission-controlled ships, already assigned ships, or unsupported candidates.

## Installation

### Steam Workshop

1. Subscribe on the [Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3778882957).
2. Subscribe to the required [UI Extensions and HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3477279743) dependency if Steam does not add it automatically.
3. Allow Steam to download both items.
4. Start X4 and confirm both extensions are enabled.
5. Load a save and wait approximately **10 seconds** for EOC initialization to complete.
6. Press **Control + H** anywhere, or use **Dock Interactions** while seated in the Personal Office.

### Manual installation

1. Download or clone this repository.
2. Copy `JK_Station_Manager` into the X4 `extensions` directory.
3. Ensure `content.xml` is directly inside `extensions/JK_Station_Manager`.
4. Install and enable [UI Extensions and HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3477279743).
5. Restart X4, enable both extensions, load a save, and wait approximately **10 seconds** before opening EOC.

## First-time setup

1. Load the game and wait for the EOC initialization cycle to finish.
2. Press **Control + H** and open the EOC Management Window. While seated in the Personal Office, you may instead use **Dock Interactions** and select **OPEN EXECUTIVE OPERATIONS CENTER**.
3. Open **Stations** and review station roles.
4. Use **Global Settings** to choose Advisor or Managed Trade and the desired ship-assignment authority.
5. In **Fleet & Logistics**, register suitable unassigned ships and review the status and next-step guidance.
6. Scan Shipping Needs. In Approval Required mode, review Pending and authorize only the displayed assignment. In Auto-Assign mode, review Registered Ships and the completion status.
7. Review Diagnostics, Cases, and Reports for current evidence and recommended actions.

## Documentation

- **[EOC 1.8 GA User Guide](docs/EOC_1.8_GA_USER_GUIDE.md)** - current startup, controls, workflows, feedback, navigation, and troubleshooting.
- **[EOC 1.8 GA Release Notes](docs/RELEASE_NOTES_1.8_GA.md)** - changes introduced in this release.
- **[Illustrated EOC 1.6 GA New User Guide](docs/EOC_1.6_GA_New_User_Guide.pdf)** - illustrated reference for the core EOC interface and concepts.

## Repository layout

- `JK_Station_Manager/` - clean runtime extension files required by X4.
- `docs/EOC_1.8_GA_USER_GUIDE.md` - current player guide.
- `docs/RELEASE_NOTES_1.8_GA.md` - current GA release summary.
- `docs/EOC_1.6_GA_New_User_Guide.pdf` - illustrated core-interface reference.
- `docs/images/` - public documentation artwork.

Internal test plans, debug snapshots, engineering handoffs, and development archives are intentionally excluded from the public GA repository.

## Reporting a problem

Include the X4 version, EOC version, exact preceding action, a screenshot, and the relevant X4 debug log when available. Please separate EOC errors from unrelated third-party mod errors whenever possible.

## License

This repository is licensed under the [MIT License](LICENSE).
