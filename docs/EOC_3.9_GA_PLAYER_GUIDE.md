# EOC 3.9 GA Illustrated Player Guide

EOC 3.9 is command-first: read the conclusion, follow the single next instruction, and open Deep Dive only when you want the supporting evidence.

The screenshots below are curated runtime illustrations captured during 3.9 development. Their filenames retain the exact capture build for provenance; Build 339 inherits the illustrated surfaces unless this guide explicitly describes a later change.

## Open EOC

Open the normal Ship Interactions menu and select **OPEN EXECUTIVE OPERATIONS CENTER**.

![Open EOC from Ship Interactions](images/EOC_ACCESS_SHIP_INTERACTIONS_BUILD327_2026-08-26.png)

## Read a station's story

Overview → Station Story collects retained activity for the selected station and provides direct paths to its Cases and Diagnostics.

![Overview Station Story](images/EOC_OVERVIEW_STATION_STORY_BUILD327_2026-08-26.png)

## Find and understand predictive risks

Predictive Intelligence ranks actionable risks from retained Supply evidence. Open a forecast to see confidence, measured evidence, business impact, and the exact return path.

![Predictive ranked risks](images/EOC_KPI_PREDICTIVE_RANKED_RISKS_BUILD327_2026-08-26.png)

![Predictive forecast detail](images/EOC_KPI_PREDICTIVE_FORECAST_DETAIL_BUILD327_2026-08-26.png)

## Read station performance

Top Earners compares current station-account values and credit movement with the start of the selected sampling window.

![KPI Top Earners](images/EOC_KPI_TOP_EARNERS_BUILD327_2026-08-26.png)

## Read Supply Model

The Empire Supply Balance grid shows severity, hourly shortage or surplus, coverage, and change from the prior explicit snapshot. `/h` means units per game hour; it is a rate, not current inventory.

![Supply resource grid](images/EOC_SUPPLY_RESOURCE_GRID_BUILD327_2026-08-26.png)

Open a resource to see the plain-language conclusion, installed supply, internal demand, coverage meaning, and what the snapshot cannot prove.

![Supply resource detail](images/EOC_SUPPLY_RESOURCE_DETAIL_BUILD327_2026-08-26.png)

## Review logistics coverage

Unified Logistics Coverage separates actionable conditions, stations awaiting evidence, and covered resources. Unknown ship, route, reservation, or throughput evidence remains unknown rather than being treated as zero.

![Unified Logistics Coverage](images/EOC_FLEET_LOGISTICS_COVERAGE_BUILD327_2026-08-26.png)

## Work with Cases

Cases retain exact station and subject evidence and prevent duplicate station/subject investigations. Build 339 presents the conclusion and next action before evidence; use Deep Dive for the technical record.

![Cases and retained evidence](images/EOC_CASES_ACTIVE_CASE_LIST_BUILD327_2026-08-26.png)

## Ask EOC to verify a result

Request verification once. EOC stores the exact station, subject, severity, and amount baseline, then uses the next completed established empire-analysis cycle to compare fresh evidence. You do not need to keep EOC open, certify that time passed, or request another snapshot.

While the job is active, do not enter Station Build mode. EOC reports **TEST COMPLETE** when finished, releases that restriction, and returns the supported result through a notification, Logbook entry, and retained EOC status.

The bounded cycle is normally scheduled at five-minute intervals, but total completion time also depends on where the request lands relative to the current cycle and the size of the empire.

## Evidence and player authority

`UNKNOWN` means EOC lacks required evidence; it never means zero, safe, or complete. Preview and confirmation remain separate for gameplay mutations. EOC 3.9 adds no free ships, unauthorized construction, cargo or credit movement, watcher, countdown, or per-frame analysis.

For reproducible problems, [open a GitHub issue](https://github.com/razoreqx1/JK-Empire-Operations/issues) with the EOC build, X4 version, reproduction steps, relevant mods, and a fresh debug log.
