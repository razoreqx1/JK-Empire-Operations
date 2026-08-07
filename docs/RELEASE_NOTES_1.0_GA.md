# EOC 1.0 GA Release Notes

EOC 1.0 GA is the first public general-availability release of the Executive Operations Center for X4: Foundations.

## Highlights

- Empire dashboard with Critical, Warning, and Action station lists.
- Persistent station-role classification and role-aware intelligence.
- Executive Advisor navigation and station-focused reports.
- Long-term observation and chronic issue classification.
- Operational remediation with diagnosis, evidence, recommendations, player instructions, and verification.
- Multi-page Empire Executive and remediation reports written to the X4 Tips log.
- Player-controlled managed trade orders for supported buy and sell blockers.
- Ship lifecycle awareness and capability-level ship recommendations.
- Registered-ship assignment with Disabled, Approval Required, and Auto-Assign modes.
- Filtering that excludes drones, units, XS craft, current-player ships, mission-controlled ships, assigned ships, combat-purpose ships, and unsupported candidates.
- Immediate ticker feedback for analyses, reports, control changes, and assignments.

## Supported game version

EOC 1.0 GA requires **X4: Foundations 9.0 or newer**.

X4 8.0 cannot parse two Mission Director constants used by this release. The failure can prevent the central station manager from initializing and may produce null values in EOC menus. Backward compatibility is being investigated separately and will require testing on an actual X4 8.0 environment before release.

## Known boundaries

- EOC does not purchase ships, blueprints, variants, or equipment.
- Ship recommendations describe general capability rather than a race-specific design.
- Ship assignment occurs only when a verified station need and a supported candidate are available.
- A suitable unassigned ship can remain untouched when no station currently needs that capability.
- Mod-added ships are not hard-coded and other mods are not required dependencies. Unsupported candidates remain untouched.
- Managed trade-offer quantities are based on the difference between current and target station stock; X4's station manager determines individual shipment sizes.

## Documentation

See the [EOC 1.0 GA New User Guide](EOC_1.0_GA_New_User_Guide.pdf) for illustrated installation, setup, operation, and troubleshooting instructions.
