# EOC 2.4 GA — Build 170

## Guided Recovery

- Separates the first blocker, evidence, player action, and verification into clear views.
- Presents one step at a time without pretending an action succeeded.
- Fresh verification reports **RESOLVED**, **IMPROVING**, **UNCHANGED**, or **WORSENING**.

## Stable market-test binding

- Compact diagnostic cases carry their source class and source index.
- Confirmation resolves the original critical or warning case directly.
- The exact station object and ware object are used; displayed names are not the primary binding.
- No offer is created unless both station and ware resolve.

## Bounded and reversible market tests

- Creates one evidence-sized NPC-enabled BUY or SELL test offer.
- Preserves the existing ware-specific trade rule and ordinary offers.
- Removes only EOC's matching test offer.
- Creation and completed removal are locked against repeat submissions.

## Consistent confirmation language

Amber pending-confirmation buttons now identify market creation, market removal, fleet-template deletion, fleet-build submission, one-ship logistics ordering, station roles, and station policies. A preview is visually distinct from a completed action.

## Making a successful test permanent

EOC does not automatically convert a bounded test into permanent policy. Open the station Logical Overview, select the tested ware's buy or sell offer, and change only its ware-specific trade rule. Change a station-wide rule only when the wider effect is intentional.

## Preserved capabilities

EOC 2.4 retains executive intelligence, station roles and policies, cases, reports, managed trade, shipping control, fleet templates, distributed player-yard construction, Personal Office access, named command intelligence, truthful verification, color-coded evidence, and the guided startup sequence.

## Verified before GA promotion

- Player-tested exact Ice station/ware resolution and bounded BUY creation.
- Existing ware rule preservation confirmed in the UI and debug log.
- Exact test-offer removal confirmed; ordinary offers remained untouched.
- Amber confirmation behavior and creation/removal locks verified.
- No EOC Lua or Mission Director errors in on-load, post-action, removal, or exit reviews.
- Build 170 passed 12 XML parses, full-description preservation, Steam's 7,999-byte description limit, stale-identity scans, and one-folder ZIP validation.