# Travel Planner — iOS

Native SwiftUI edition of Travel Planner. Swift 6 · SwiftUI · SwiftData ·
iOS 17.0+ · iPhone only · bundle ID `com.parthey.travelplanner`.

The web edition lives in `../web`; both price from the same shared
dataset — see `../../docs/PARITY.md`.

## Build

Open `TravelPlanner/TravelPlanner.xcodeproj` in Xcode 16+, pick the
**TravelPlanner** scheme, run. No packages, no pods, no network keys —
everything prices on-device from the bundled dataset.

Tests: `TravelPlannerTests` (pricing goldens, dataset anchors, phase
logic) — run with ⌘U or in CI (`.github/workflows/ci.yml` runs them on a
simulator; `release.yml` archives for TestFlight once the ASC secrets
exist — `../../docs/PUBLISHING.md`).

## Structure

```
TravelPlanner/
  TravelPlannerApp.swift     app entry, SwiftData container
  Design/Theme.swift         jet-black design tokens, shared components
  Models/                    enums + SwiftData models (Profile, Trip,
                             HotelVariant, ComparePick, BrochureRequest,
                             PlannerSettings, CustomDestination)
  Catalog/Catalog.swift      Decodable mirror of packages/dataset
  Pricing/                   contract protocols, engine, providers,
                             memoising PricingService
  Services/                  view prefs (UserDefaults), phase logic,
                             seeding, brochure generation
  Views/                     onboarding, Explore, Trips, editor, pass
                             panel, Compare, brochures, More/Profile
  Resources/                 Assets.xcassets (icon, accent, 6 bundled
                             destination photos), dataset.json (copy of
                             packages/dataset — CI drift-checked)
TravelPlannerTests/          XCTest suite
ExportOptions.plist          TestFlight export (team ID placeholder)
```

## Rules baked in

- Jet black #000 + white only — no theme toggle, no Appearance setting.
- Breakdown lives only in the trip editor; cards show the total only.
- Compare is opt-in only (max 3); nothing auto-populates it.
- "Queued for assistant" is the only brochure state the app claims
  until a human marks it sent.
- View prefs (sorts/filters/tabs) live in UserDefaults and never feed
  pricing.
