# EOC 3.8 GA Player Guide

EOC is designed to answer three questions: **What is happening? Who needs to act? What should happen next?**

## Start with the plain-language result

Open the page that interests you and read its verdict or command summary first. Supporting evidence appears below it for players who want to verify the conclusion.

## Reading Supply Model

- `/h` means **units per game hour**. It is a rate, not the number of units currently stored.
- `100% coverage` means measured supply exactly equals measured demand.
- Below `100%` means measured supply is insufficient for measured demand.
- Above `100%` means measured production capacity exceeds measured demand. It is not a score and does not automatically mean the station is healthy.
- Stored inventory answers “how much is here now.” Supply and demand rates answer “how quickly it can be made or used.”

The Supply snapshot does not automatically prove how many ships are currently flying, whether a buyer is available, whether a route is blocked, or whether prices and trade permissions allow a sale. EOC identifies those unknowns instead of treating them as zero.

## Reading Storage

Storage is ranked with the fullest station first. Green is below 80%, amber is 80% through 89.9%, and red is 90% or higher. The change value compares the current live sample with the prior live sample; `+0.0 points` means no measurable percentage-point change occurred between those samples.

## Reading Executive Attention

Executive Attention is a priority list, not a performance score. It shows the station's current state, the number of related issues, and a plain-language reason for its position.

## Reading Cases

Begin with the command summary:

- **NO PLAYER ACTION RIGHT NOW** means EOC is handling the bounded action it is authorized to perform.
- **PLAYER ACTION REQUIRED** means EOC has reached a step it cannot safely perform for you.
- **WAITING FOR TRADE CYCLE** means EOC is waiting for the station manager or an NPC buyer to complete a permitted movement of the named ware. There is no fixed timer; it depends on an eligible trade actually occurring.

If an investigation already exists, EOC opens that Case. It does not create a duplicate.

## Price and storage recommendations

Read the explanation before previewing a change. The current value is what X4 reports. The EOC suggestion is advisory. A proposed value does nothing until you preview and deliberately confirm it. Storage changes affect ware allocation, not the station's physical storage-module capacity.

## Verifying an EOC result

Use the exact station and ware named in EOC when comparing against the vanilla station screen. Remember that EOC shows the last analysis snapshot until another explicit analysis or verification runs. `UNKNOWN` means EOC lacks the required evidence; it does not mean zero or safe.

For a reproducible problem, open a [GitHub issue](https://github.com/razoreqx1/JK-Empire-Operations/issues) with the EOC build, X4 version, station and ware, reproduction steps, relevant mods, and a fresh debug log.
