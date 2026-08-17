# EOC 3.2 GA User and Support Guide

## Starting EOC

After loading a game, wait approximately 10 seconds for EOC to complete its initial station scan. Open Dock Interactions and select **OPEN EXECUTIVE OPERATIONS CENTER**. The obsolete conversation pinwheel was retired in Build 253.

## KPI Center

The KPI Center samples live information every 10 seconds only while it is open. Native Player Wealth, Case Trends, and Empire Growth graphs support 5, 10, and 30-minute ranges.

Detailed KPI views use bounded five-row pages. Previous and Next controls provide access to the retained applicable dataset without exceeding X4's menu-height limits. Automatic sampling preserves the active page.

Shipyard Activity reports ships queued, active, and retained in completed history. Station-module construction is not counted as ship workload.

## Cases and station status

**CLEAR ALL EOC CASES** requires two deliberate confirmations. It clears EOC player cases, monitored cases, critical and warning cases, retained observation evidence, remediation records, and transient investigation pointers. It does not alter stations, ships, orders, construction, funds, roles, or settings.

Immediately after clearing, station profiles return to **MONITORING / STABLE**. Later non-healthy classifications require a visible matching case or retained observation evidence.

Cases include a two-way command checklist. EOC-owned rows update only from supported live evidence. Player decision rows can record Yes/Done, No/Not Done, or remain unanswered. An answer does not independently cancel a managed action; later evidence controls resolution.

## Fleet visibility and minimums

Fleet & Logistics distinguishes EOC-registered ships from compatible ships that are available but not registered. Visibility does not grant control.

Global minimums for mining, trade, build-storage trade, defence, and escorts default to zero. Assignments remain bounded by the selected authority mode and never remove existing assignments merely because a minimum changes.

## Performance

Shipyard reconciliation runs every five minutes. Construction automation and ship/remediation matching run every two minutes. KPI histories and visible result windows are bounded.

## Player authority

EOC remains advisory unless you grant the relevant authority and deliberately confirm an action. It does not create free ships, bypass normal construction resources, or make unauthorized credit movements.

## Troubleshooting

- Confirm Extensions shows **EOC 3.2 GA**.
- Wait for the readiness summary before opening EOC after loading.
- If a station shows a non-monitoring status, open its Cases view and confirm the supporting case or retained evidence is visible.
- Report the affected page, selected filter, exact visible message, EOC build/version, X4 version, reproduction steps, relevant mods, and a fresh debug log.

Issue tracker: https://github.com/razoreqx1/JK-Empire-Operations/issues

Support community: https://discord.gg/qp8pmuWqtt
