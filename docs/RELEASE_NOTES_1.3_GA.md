# EOC 1.3 GA Release Notes

EOC 1.3 GA advances the Executive Operations Center with executive intelligence, cross-version compatibility, automatic station-role recovery, and corrected native logistics-ship discovery.

## Highlights

- Executive Intelligence Dashboard with empire health, economy, logistics, workforce, defense, growth, station health, production efficiency, ship utilization, active cases, and stations requiring attention.
- Trend and "What Changed?" intelligence covering new, resolved, worsening, and improving conditions.
- Cross-version initialization safeguards for X4: Foundations 8.0 and 9.0.
- Player-facing information entries are identified clearly in conversation menus.
- Station names are displayed as supplied by X4 or the player without EOC-specific tag stripping.
- Automatic role assignment is available directly from Station Role Assignment.
- Undefined station roles are assigned automatically after three observation cycles when the player does not classify them manually.
- Every automatic role includes evidence in Tips and remains manually editable.
- Native free-ship discovery correctly identifies eligible unassigned trade and mining ships.
- Registered ships can be matched and assigned only to evidence-supported station logistics requirements.
- Separate safeguards continue to exclude fleet leaders, ships with subordinates, drones, units, XS craft, unsupported purposes, the player's current ship, assigned ships, and unsupported cargo types.

## Player-controlled automation

- **Instructions only:** EOC diagnoses and explains without executing changes.
- **Approval required:** EOC presents the exact supported assignment before acting.
- **Auto-assign registered ships:** EOC may assign only supported registered candidates to verified station needs.
- **Managed trade orders:** Remains a separate opt-in capability that can be disabled later.

## Known boundaries

- EOC does not purchase ships, blueprints, variants, or equipment.
- Ship recommendations describe general capability rather than a race-specific design.
- A suitable unassigned ship remains untouched when no verified station need exists.
- Mod-added ships are not hard-coded, and no external mod is required.
- Unsupported or protected candidates remain untouched.
- Managed trade-offer quantities use the observed difference between current and target station stock; X4's station manager determines individual shipment sizes.

## Documentation

See the [illustrated EOC New User Guide](EOC_1.0_GA_New_User_Guide.pdf) for installation, setup, core operation, and troubleshooting. The new 1.3 capabilities are summarized above.
