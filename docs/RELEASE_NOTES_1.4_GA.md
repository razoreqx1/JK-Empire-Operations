# EOC 1.4 GA Release Notes

EOC 1.4 GA introduces the Lua Operations Console while preserving the verified EOC operational backend and original pinwheel workflow.

## Highlights

- Persistent **Stations**, **Dashboard**, and **Global Settings** navigation in a native-style Lua interface.
- A unified station workspace for station roles, operational controls, and station reports.
- Selected-station synchronization across displayed intelligence and controls.
- Clear selected-state behavior for tabs, trade mode, ship assignment, and assignment authority.
- Direct access to the Operations Console while preserving the original EOC pinwheel.
- Preserved Executive Analysis, Tips report delivery, native Back/Escape navigation, and Mission Director-owned business logic.
- Continued X4: Foundations 8.x and 9.x compatibility.
- Preserved logistics safety controls from EOC 1.3 GA.

## Getting started

Press **Control + H** to open EOC. Choose the Operations Console for the Lua interface or continue using the EOC pinwheel. Assign persistent roles to your stations, run Executive Analysis, and use the Executive Advisor to review evidence and recommended actions. Detailed reports are saved in the Logbook Tips tab.

## Known boundaries

- The optional inline Dashboard analysis and report output boxes remain deferred visual enhancements. Analysis and report generation continue to work, and reports are saved to Tips.
- EOC does not purchase ships, blueprints, variants, or equipment.
- Ship recommendations describe general capability rather than a race-specific design.
- A suitable unassigned ship remains untouched when no verified station need exists.
- Mod-added ships are not hard-coded, and no external mod is required.
- Unsupported or protected candidates remain untouched.

## Documentation

See the [illustrated EOC New User Guide](EOC_1.0_GA_New_User_Guide.pdf) for installation, setup, core operation, and troubleshooting. The Lua Operations Console additions are summarized above.
