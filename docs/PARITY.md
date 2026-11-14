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
   Epic Pass panel; opt-in Compare (starts empty, max 3, white LOWEST
   cells); brochure chooser (primaries pre-ticked) + queued brochures
   with the honest "Queued for assistant" state; Profile form; planner
   settings; About & data sources. Jet black #000 + white only on both —
   no theme toggle anywhere.
4. **Same honesty rules.** Coming-soon trip types and custom places are
   saveable but never priced with invented numbers; "Queued" never
   claims "Sent"; partial totals are labelled partial.

## Known differences (accepted, not bugs)

| Area | iOS | Web |
|---|---|---|
| Storage | SwiftData on-device | Browser `localStorage` — per browser, no sync between the two editions (v2 topic) |
| Destination photos | Bundled JPEG assets (works offline) | The same six photos loaded from remote URLs, with the designed gradient fallback if a host blocks hotlinking |
| Brochure PDF | Native one-page PDF generated in-app, shareable | Print / save-as-PDF from the browser; brochure text identical, downloadable as `.txt` |
| Brochure sending | Queued for the assistant / share sheet | Same queue semantics; download/print are the local export paths |
| Release | TestFlight → App Store (owner's Submit tap) | GitHub Pages on push to `main` (no gate) |
| Tests | XCTest suite (pricing goldens, dataset anchors, phase logic) | Node goldens harness (`apps/web/tests/goldens.mjs`) asserting the same figures |
| Accessibility | Dynamic Type, VoiceOver labels, ≥44pt targets | Semantic HTML, visible focus, ≥44px targets; full screen-reader audit still to do |

Anything not listed here that differs between the editions is a parity
bug — file it against this contract.
