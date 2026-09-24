# EOC 3.9 Build 404 Release Notes

Build 404 adds independent persistent controls for EOC's three main background feature groups while preserving existing data, manual tools, and separate player authorities.

## Global feature switches

- **Background Empire Analysis** controls new scheduled empire-analysis work.
- **Automatic Remediation Review** controls new scheduled remediation review.
- **Automatic Ship Matching** controls new scheduled registered-ship matching.
- Green is ON; yellow is OFF.
- Each click saves immediately without confirmation.
- Each switch changes only its own exact binary value: `1` is ON and `0` is OFF.

All three saved values are delivered together when EOC opens and are applied before the Settings page first renders. This prevents an old delayed readback from redrawing unrelated controls after a click.

## What OFF preserves

Turning a feature OFF stops new scheduled work for that feature. It preserves existing reports, cases, evidence, history, receipts, paid or in-flight work, manual actions, and the separate trade, construction-funding, and ship-assignment authorities.

## Runtime acceptance

Live X4 testing confirmed:

- all three controls changed independently;
- OFF and ON states persisted across save/reload;
- the correct saved state appeared when EOC reopened;
- analysis capacity sampling resumed when analysis was enabled;
- remediation review completed a cycle when remediation was enabled;
- shipping initialized and completed build-storage and salvage scans when ship matching was enabled;
- no related EOC Lua or XML runtime failure followed the switch changes.

Extended-session performance, alternate saves, every possible automatic outcome, and universal mod compatibility remain runtime dependent.

## Compatibility warning

Another automatic trading or ship-management mod may compete with EOC for the same idle ships. If assignments repeatedly change, disable one automation system or use EOC's **Approval Required** mode. This warning is general compatibility guidance, not proof that a specific mod is conflicting.

Build 404 preserves Build 397's accepted case lifecycle, exact confirmed station-expansion workflow, construction-progress routing, and visible version identity.

Report reproducible issues at <https://github.com/razoreqx1/JK-Empire-Operations/issues> and include Build 404/version 504, the three switch states, exact reproduction steps, affected station or ship, relevant mods, and a fresh X4 debug log.
