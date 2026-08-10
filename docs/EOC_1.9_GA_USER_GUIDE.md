# EOC 1.9 GA User Guide

## Start EOC safely

1. Load your save.
2. EOC displays an initialization notice immediately.
3. Wait approximately **10 seconds** for initialization and the player-property scan to complete.
4. Press **Control + H**, or use **Open Executive Operations Center** while seated in the Personal Office.

## Main tabs

- **Stations** — select a station, review its role and issues, and open contextual workflows. The selected station remains black until you choose another.
- **Overview** — empire health, KPIs, trends, and recent changes.
- **KPI Center** — ranked station attention and read-only operational measures.
- **Fleet & Logistics** — registered ships, shipping needs, pending approvals, and EOC trade-order review.
- **Diagnostics** — guided recovery, prerequisite evidence, supplier checks, and recovery verification.
- **Cases** — active operational issues ordered by importance.
- **Reports** — completed EOC report history and action results.
- **Global Settings** — trade authority, ship-assignment authority, operating policy, and station-role automation.

## Working-station context

Select a station from **Stations** before opening Cases or Diagnostics. EOC keeps that station as the working context across the workflow and provides truthful return paths. In the station navigator, its button remains black until another station is selected; blue remains normal hover or focus feedback.

## Guided Recovery

1. Select an actionable station issue.
2. Open **Diagnostics** and remain on **Guided Recovery**.
3. Review the full-width prerequisite results.
4. Read each **PASS**, **FAIL**, or **UNKNOWN** result and its evidence.
5. Follow the single **NEXT PLAYER ACTION** for the first failed or unknown prerequisite.

EOC may analyze, monitor, report, or run an explicitly enabled bounded action. Ordinary station configuration, funding, construction, and ship orders remain player decisions.

## Verify Recovery

After completing the recommended player action:

1. Open **Verify Recovery**.
2. Select **Verify: Run Fresh Analysis** once.
3. The button blacks out while EOC rescans the working case.
4. Wait for one terminal result:
   - **RESOLVED** — the rescanned case is no longer present.
   - **IMPROVING** — current evidence is better than the prior case.
   - **UNCHANGED** — the same condition remains at the same level.
   - **WORSENING** — current evidence or severity has deteriorated.
5. Use **Return to Guided Recovery** to continue with the same station and case.

## Action lifecycle

Analysis, scans, reports, registrations, approvals, role or policy changes, and proofs disable or black out while work is pending. Their color returns only after EOC receives a terminal result or finding. Navigation and return controls remain available so the player is not trapped.

Do not repeatedly click a blacked-out action. Read the resulting **STATUS**, **NEXT STEP**, or contextual **VIEW RESULT** route.

## Authority settings

### Trade Order Control

- **Advisor Mode** gives instructions only.
- **Managed Trade** permits EOC to create evidence-supported EOC trade offers.

### Ship Assignment Authority

- **Disabled** prevents EOC ship assignment.
- **Approval Required** creates a proposal for player review.
- **Auto-Assign Registered** allows assignment only from eligible ships already registered with EOC.

## Register ships and scan needs

1. Open **Fleet & Logistics**.
2. Select **Register Suitable Unassigned Ships** once.
3. Wait for the terminal result and read **STATUS** and **NEXT STEP**.
4. Review **Registered Ships** if directed there.
5. Select **Scan Shipping Needs** once and wait for its result.

Registration does not create artificial demand. An eligible ship may remain available until EOC finds a compatible supported need.

## Reports and results

Completed report generation routes to **Reports** and preserves the return path. A completed asynchronous action may offer a contextual **View Result** route. Report generation and other one-shot controls remain unavailable while their work is pending.

## Safety boundaries

- EOC does not buy ships, blueprints, variants, or equipment.
- It does not intentionally take drones, units, XS craft, the player's current ship, mission-controlled ships, assigned ships, or unsupported candidates.
- The legacy bounded supply action that cancels a trader's existing orders is not exposed because restoration of prior orders and assignment has not been proven safe.
- Developer permission probes are not exposed in the player interface.

## Troubleshooting

- If EOC seems incomplete immediately after loading, close it, wait for initialization to finish, and reopen it.
- If an action is blacked out, wait for its terminal result before trying again.
- If verification reports **UNCHANGED**, the rescan succeeded but the underlying condition remains.
- If Pending is empty, no supported need with a compatible registered ship is awaiting approval.
- For issue reports, include the X4 version, EOC version, preceding action, screenshot, and relevant debug-log section.