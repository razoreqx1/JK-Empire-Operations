# EOC 1.9 GA Release Notes

EOC 1.9 GA turns station cases into actionable recovery workflows while improving menu stability, working-station context, and asynchronous action feedback.

## Actionable Guided Recovery

- Sends station prerequisite evidence into the EOC interface.
- Shows full-width **PASS / FAIL / UNKNOWN** prerequisite results.
- Identifies the first failed or unknown check.
- Provides one specific next player action.
- Supports issue families generally rather than presenting Allographyne-only guidance.

## Real recovery verification

- **Verify: Run Fresh Analysis** performs a fresh station and case rescan.
- Reports **RESOLVED**, **IMPROVING**, **UNCHANGED**, or **WORSENING**.
- Displays the rescanned evidence and retains the working case context.

## Deterministic action lifecycle

- Analysis, scans, reports, registrations, approvals, role and policy changes, and proofs black out while pending.
- Controls become available again only after EOC returns a terminal result or finding.
- Navigation controls remain available.
- Contextual result and Reports routes preserve truthful return paths.

## Interface clarity and stability

- The selected station remains black until another station is selected.
- Critical results use full-width wrapped text.
- Fixes the prerequisite-row data mismatch that could break the shared EOC menu.
- Removes player access to developer permission probes.

## Safety

- The legacy supply action that cancels a trader's orders remains unexposed because restoration of previous orders and assignment is not proven.
- Ordinary configuration, funding, construction, and ship orders remain player decisions.
- Compatible with X4: Foundations 8.x and 9.x.

## Upgrade

Steam Workshop subscribers receive EOC 1.9 GA automatically. Manual users should replace the existing `JK_Station_Manager` folder with the clean repository folder, restart X4, load a save, and wait approximately 10 seconds before opening EOC.