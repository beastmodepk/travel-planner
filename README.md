# Travel Planner

Plan trips side by side — pick a trip type, set dates and travel style, and the app prices everything: flights, hotels, passes/tickets and gear — with booking links on every line.

Trips can be about anything. The first fully priced type is **Ski — West Coast** (Park City, Tahoe–Heavenly, Alta/Snowbird, Jackson Hole, Breckenridge); more types (Beach, City break, Adventure, Family) are added over time behind the same provider contracts.

**Status:** prototype built in Muse (black & white — matte or pure black — sleek, personalized onboarding). This repo holds the portable codebase: the pricing/email backends sit behind provider contracts so the app can be deployed anywhere, published on GitHub, and carried to an iPhone app, with an AI model attachable for live price research.

## How it works

- **Two trip cards** — destination, date window, ski days (3–4), style preset (Cheap / Balanced / Expensive / Best Social / Best Snow), fare class, gear choice.
- **Cards lock while pricing** — no edits mid-calculation.
- **Smart pass logic** — across both trips, the engine compares one multi-day Epic Day Pass vs separate passes vs a full season pass, and recommends the cheapest.
- **Get Brochure Email** — generates a brochure PDF + plain-text email of the current plan and sends it via the configured email provider.
- **Personalization** — an Atomic-Habits-style onboarding (level, terrain, budget, vibe, gear, passes) sets smart defaults everywhere; editable anytime in Profile.

## Architecture

| Layer | Role |
|---|---|
| UI | Onboarding, planner, profile — consumes only provider contract output |
| Pricing engine | Trip maths, pass recommendation, totals — provider-agnostic |
| `PricingProvider` | Contract: trip in → structured flights/hotels/lifts/rentals/links out |
| `DatasetProvider` | Ships researched prices (checked Nov 13, 2026) — works with zero keys |
| `AiResearchProvider` | Slot for an AI model to do live pricing research into the same schema |
| `EmailProvider` | Contract for sending brochure emails; credentials are deploy-time secrets |

## Configuration (keys provided at deploy time)

Copy `.env.example` to `.env` and fill in what you use. **The app runs fully with no keys set** — dataset pricing + queued email are the defaults. Never commit a real `.env`.

## Data note

Built-in prices were researched on Nov 13, 2026 (flights via Duffel, hotels via Expedia, lift tickets from official resort shops). Every priced line carries its source and check date; figures marked ~ are estimates.

## Monorepo layout (added 2026-11-13)

This repo is now the single home for the whole product:

| Path | What lives there |
|---|---|
| `apps/ios/` | **Travel Planner for iPhone** — native Swift 6 / SwiftUI app (iOS 17+), bundle ID `com.parthey.travelplanner`. See `apps/ios/README.md`. |
| `apps/web/` | **Travel Planner for the web** — the same v1.0 features as iOS, dependency-free static site, live at <https://beastmodepk.github.io/travel-planner/> (deployed by `pages.yml`). See `apps/web/README.md` and `docs/PARITY.md`. |
| `packages/dataset/` | `dataset.json` — the researched price catalog (checked Nov 13, 2026). **Single source of truth** for web and iOS; `dataset.schema.json` + `CHANGELOG.md` alongside. |
| `packages/contracts/` | The `PricingProvider` / `EmailProvider` contract definitions and JSON payload schemas both apps implement. |
| `docs/` | `PARITY.md` (the web↔iOS parity contract), `PRIVACY.md` (App Store: Data Not Collected), `VERSIONING.md` (house standard), `PUBLISHING.md` (owner gates + the secrets Parthey adds later). |
| `.github/workflows/` | `ci.yml` (structural checks + unsigned build/test, no secrets needed), `release.yml` (house release pipeline: merge to `main` → signed archive → TestFlight; **dry-runs unsigned until the ASC secrets exist**), `pages.yml` (deploys `apps/web` to GitHub Pages). |

The Muse web prototype remains the concept proving ground; its pricing maths was
ported 1:1 into both the iOS pricing engine and the web engine, and its
verified totals are the test goldens on both sides.

**Keys:** the iOS app needs no keys to run. Signing/TestFlight activates when
Parthey adds four GitHub secrets — `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
`ASC_TEAM_ID` — plus the App Store Connect app record. Full steps:
`docs/PUBLISHING.md`.
