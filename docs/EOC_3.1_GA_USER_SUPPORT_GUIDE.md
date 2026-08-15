# EOC 3.1 GA User and Support Guide

## Starting EOC

After loading a game, wait approximately 10 seconds for EOC to complete its initial station scan. Open Dock Interactions and select **OPEN EXECUTIVE OPERATIONS CENTER**, or use the EOC pinwheel.

## Dock Interactions support evidence

EOC 3.1 GA records a bounded event trail for support: callback registration, button rendering, button selection, open-event raise, and open-event receipt. Registration stops after success and does not run as a recurring watchdog.

If the button is missing, report which of those stages appears in the X4 debug log. Do not infer an EOC failure from unrelated game or mod errors in the same log.

## Using the KPI Center

The KPI Center samples live information every 10 seconds only while it is open. Automatic refresh preserves the visible text window. Use each filtering dropdown's **ALL** option to return to the complete applicable dataset.

KPI views display at most eight data rows to remain within X4's safe widget height. When more rows exist, EOC reports the visible and hidden counts; select a narrower filter for detail.

Construction Progress shows one compact row per station in the all-stations view. Selecting a station opens its bounded module drilldown.

## Player authority

EOC recommendations remain advisory unless you grant the relevant authority and deliberately confirm an action. EOC does not create free ships, bypass normal construction resources, or make unauthorized credit movements.

## Troubleshooting

- Confirm EOC shows version **3.1 GA** in Extensions.
- Wait for the readiness summary before opening EOC after loading.
- If a KPI filter seems inactive, select **ALL** and then reselect the intended station or shipyard.
- Report the affected view, selected filter, exact visible message, and relevant EOC debug markers when requesting support.

Support community: https://discord.gg/qp8pmuWqtt
