# Web ↔ iOS parity contract

Travel Planner ships as two editions of the **same product**:

- **iOS** — `apps/ios` (SwiftUI, SwiftData), App Store / TestFlight.
- **Web** — `apps/web` (dependency-free static site), GitHub Pages at
  <https://beastmodepk.github.io/travel-planner/>.

## The contract

1. **Same dataset.** Both editions price from
   `packages/dataset/dataset.json` (checked 2026-11-13). Each edition
   carries a byte-identical copy (iOS: bundled resource; web:
   `apps/web/dataset.json`); CI fails if any copy drifts.
2. **Same pricing semantics.** Same line construction, per-person
   scaling, hotel-night proration, gear auto-selection
   (cheapest excluding premium), Epic Pass engine (combined vs separate
   vs full; >10 pass days → full pass; pro-rata allocation with the last
   trip absorbing rounding), held-pass $0, and the same "estimates are
   flagged, unknowns stay unpriced" honesty rule. Both engines assert the
   same goldens (default plan $3,112.43; Niseko Jan comfort $1,997.21;
   6-day pass $640 over $772/$1,169).
3. **Same feature list (v1.0).** Ten-question onboarding with skip +
   payoff; Explore gallery (default filter "All types", price-from);
   Trips with the four manual phases, phase suggestions (never
   automatic), display-only sort/filter, collapsed Past section; trip
   editor with the breakdown only there, hotel multi-pick (≤3, exactly
   one Primary), direct Expedia deep links, text fields that never lock;
   opt-in Compare (starts empty, max 3, white LOWEST cells); brochure
   chooser (primaries pre-ticked) with the honest "Queued for assistant"
   state; Profile form; planner settings; About & data sources. There is
   **no Epic Pass panel** and **no queued-brochures list** on either
   edition (both removed at the owner's request): pass pricing is
   engine-only — the recommendation still lands in each trip's
   Lift / Pass line — and queued brochures are held for the assistant,
   not browsable in-app. Jet black #000 + white only on both —
   no theme toggle anywhere. Text on destination photos sits on
   **frosted-glass panels** (translucent black, backdrop blur, hairline
   white border) over a softened scrim on both editions — never on a
   solid plate that hides the picture.
   **Flights are selectable options**, Google-Flights style: each
   destination/window offers 3 options (airline, times, duration, stops,
   fare class, Best/Cheapest tags) in the editor; exactly one is selected
   and its price drives the Flight line; the default is the dataset's
   `anchor` option for the fare class, so the verified totals reproduce.
   Trip cards and the breakdown show the chosen flight's summary.
   **The trip editor is a row of picking boxes** — Basics, Flights,
   Accommodation, Lift / Pass, Gear — in that order on both editions.
   One box is open at a time (accordion): picking in a box collapses it
   and opens the next undecided box; a collapsed box shows a one-line
   summary (pick + price) and tapping it reopens it. A box is **decided
   only by an explicit user action** — a pick (flight row, Make primary,
   gear row), Done/confirm, or Skip on an optional box — and decisions
   persist per trip (web: in the saved state; iOS: in view prefs keyed
   by trip id). Priced defaults are **not** decisions: the anchor flight
   and gear "auto" leave their boxes undecided, so on load every box
   opens unless the user has decided it; changing a box's inputs
   (destination, dates, ski days, style preset) clears the affected
   decisions and reopens those boxes. Completion is display state only
   and never affects pricing. **Transfers get no box**: in both engines
   transfers are a single researched per-destination line, never a
   choice, so there is nothing to pick. The breakdown list and the
   sticky total sit below the boxes, unchanged.
4. **Same honesty rules.** Custom places are saveable but never priced
   with invented numbers; "Queued" never claims "Sent"; partial totals
   are labelled partial. The catalog carries exactly two trip types —
   Ski — West Coast and Ski — Japan (Beach, City break, Adventure and
   Family were removed at the owner's request); a saved trip or gallery
   filter naming a removed type falls back to Ski — West Coast / "All
   types" on both editions rather than breaking.

## Known differences (accepted, not bugs)

| Area | iOS | Web |
|---|---|---|
| Storage | SwiftData on-device | Browser `localStorage` — per browser, no sync between the two editions (v2 topic) |
| Destination photos | Bundled JPEG assets (works offline) | The same six photos loaded from remote URLs, with the designed gradient fallback if a host blocks hotlinking |
| Brochure PDF | Native one-page PDF generated in-app, held in the queue | Brochure text composed at queue time, held in the queue; no in-app export |
| Brochure sending | Queued for the assistant | Same queue semantics |
| Compare, empty | Tab is permanent; minimal "Nothing here yet" empty state | Compare tab is hidden until the first pick is added; the section renders only with ≥1 pick |
| Release | TestFlight → App Store (owner's Submit tap) | GitHub Pages on push to `main` (no gate) |
| Tests | XCTest suite (pricing goldens, dataset anchors, phase logic) | Node goldens harness (`apps/web/tests/goldens.mjs`) asserting the same figures |
| Accessibility | Dynamic Type, VoiceOver labels, ≥44pt targets | Semantic HTML, visible focus, ≥44px targets; full screen-reader audit still to do |

Anything not listed here that differs between the editions is a parity
bug — file it against this contract.
