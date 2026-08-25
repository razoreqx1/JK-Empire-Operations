# EOC 3.7 GA Player Guide

This guide explains how to read EOC, verify its evidence against your stations, and follow an issue from detection to resolution.

## Start here

1. Load your save and allow about 10 seconds for EOC to initialize.
2. Open **Dock Interactions**, then select **OPEN EXECUTIVE OPERATIONS CENTER**.
3. Open **KPI Center > Predictive Intelligence** for the ranked operating-risk view.

## What the Predictive views mean

- **Actionable** — EOC has enough evidence to connect the forecast to an existing Case or another governed next step.
- **Watch** — the condition is worth monitoring, but EOC does not yet have enough evidence to ask you to act.
- **All Evidence** — includes incomplete, baseline-only, and lower-confidence observations for inspection.
- **Empire Summary** — summarizes the current Predictive evidence across the empire.

Low confidence is not failure. A baseline-only forecast means EOC has one usable point of evidence but still needs a later, meaningfully separated Supply snapshot before it can claim a trend.

## How to follow an actionable issue

1. Select the station card.
2. Read the issue name, ware, evidence, confidence, business impact, and **EOC STATUS**.
3. Select the button directly beneath that issue. Its label identifies the destination, such as an exact Case or station evidence.
4. On the Case page, begin with **PLAYER COMMAND SUMMARY**. It tells you whether EOC is already handling the issue or whether you have a required action.
5. Select **OPEN GUIDED NEXT ACTION** or **SHOW ME WHAT TO DO** for the ordered recovery path.

The return control takes you back to the same Predictive filter and station detail so you can address the remaining issues without rebuilding your place manually.

## How to understand evidence

- **Current stock** is the quantity EOC observed during its last analysis. It may differ from the vanilla station screen until another analysis runs.
- **Target** is EOC's evidence-based operating target or the station's relevant allocation limit, as identified on the page.
- **Installed production/use** describes observed capacity and demand evidence; it does not prove that production is currently running.
- **Confidence** describes evidence depth. It is not severity.
- **Unknown** means EOC does not possess the required evidence. It does not mean zero, safe, or failed.
- **Business impact** is context derived from the same incident. It is not another Case.

Use **OPEN STATION** when you want to compare EOC's snapshot with the vanilla station information. Compare the same station and ware shown in the EOC working context.

## EOC responsibility versus player responsibility

- **NO PLAYER ACTION RIGHT NOW — EOC IS HANDLING THIS CASE** means EOC has an authorized bounded action underway. Allow normal game activity to occur before verifying again.
- **PLAYER ACTION REQUIRED** means EOC has reached a check or decision it cannot perform within its authority. Follow the named action on the page.
- **WAITING FOR TRADE CYCLE** means EOC is waiting for the station manager or an NPC buyer to move the named ware. This has no fixed duration and may not occur if no permitted buyer can complete the trade.
- **EOC CHECKING** means the request was accepted and duplicate submissions are blocked while it is processed.

## Verification

Run one fresh verification only after the named action or one meaningful operating, delivery, or trade event has had time to occur. EOC compares the new evidence with the retained baseline and reports **Resolved**, **Improving**, **Unchanged**, or **Worsening**.

Repeated immediate checks cannot create new game evidence. If a completed check is unchanged, follow the concrete player inspection EOC presents next.

## When EOC recommends a ship

EOC routes to a ship recommendation only when the existing Case evidence supports the cargo class, stock is below target, and no compatible logistics ship is available under the governed rules. The recommendation remains advisory until you deliberately choose the ship size, review the preview, and confirm the exact build through the existing controlled workflow.

EOC does not provide free ships, steal assigned ships, or bypass normal shipyard resources and construction.

## Reports and support

Generate a station report when you need a persistent summary. Reports remain available through EOC and the Logbook Tips system where supported by the workflow.

For a reproducible problem, open a [GitHub issue](https://github.com/razoreqx1/JK-Empire-Operations/issues) and include:

- EOC build and version
- X4 version
- Exact station and ware
- Steps that reproduce the problem
- Relevant active mods
- A fresh X4 debug log
