# EOC 3.9 GA Build413 / version513

Build413 is the identity-only GA promotion of the runtime-tested Build412 package. No gameplay logic changed during promotion.

## Dedicated Open EOC hotkey

- Adds a stable Open EOC action through Native Hotkey API.
- Assign **Control+E** once under **Options > Hotkey Management > Hotkey Bindings**.
- Routes the hotkey through EOC's existing menu-open transport.
- Leaves saved bindings and conflict resolution under X4's control; EOC does not silently rewrite the player input profile.
- Declares Native Hotkey API version 8.00.09 as a required dependency.

## Retained safeguards

- Build411 idle-construction guards remain unchanged.
- Build410 first-use ship-registration safeguards remain unchanged.
- Build409 mixed-module build sets, quantity retention, separate approval, and confirmed-order station-progress handoff remain unchanged.
- Native construction costs, eligible existing ships, and visible builder, funding, and material blockers remain unchanged.

## Acceptance coverage

RazorEQX confirmed that the hotkey binding can be assigned and Control+E opens EOC in the tested game session.

First-person opening, repeated use and close/reopen, `reloadui`, save/reload and profile persistence, clean closed-session logging, and broader mod-set compatibility remain **RUNTIME ACCEPTANCE REQUIRED**. This release does not claim universal control-profile compatibility or completion of untested construction, economic, save/reload, or native gameplay paths.
