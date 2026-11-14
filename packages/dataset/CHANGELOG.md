# Dataset changelog

All price changes to `dataset.json` land here, newest first. Prices change by
editing this package — never by editing app code.

## Unreleased — local working tree (not yet committed)

### Trip editor: picking boxes (accordion)

The editor's sections are now per-category boxes — Basics, Flights,
Accommodation, Lift / Pass, Gear — on both editions. A box collapses
when the user picks in it (or taps Done/Skip), shows a one-line summary
with the pick + price and a ✓ (or "Skipped"), reopens on tap, and the
next undecided box opens automatically. A box counts as decided **only**
by an explicit pick, confirm or skip — priced defaults (the anchor
flight, gear "auto") never mark a box decided, so undecided boxes load
open. Decisions persist per trip and are display state only; the
breakdown and sticky total are unchanged, and every golden total
reproduces. Transfers are a single researched line, not a choice, so
they get no box.

### Main-UI removals: queued-brochures list, Epic Pass panel, empty Compare

Three sections removed from both apps (UI only — no data or pricing
change; every verified golden total reproduces):

- **Queued brochures list** — the browsable queue view (web: More ›
  Brochures; iOS: More › Brochures) is gone, with its header, empty
  state and "assistant holds it to send from
  partheysmusebot@gmail.com" note. The **Get brochure email** button +
  chooser sheet stay exactly as they were; queued brochures are simply
  held for the assistant rather than listed in-app. (The About & data
  sources provenance copy was *not* touched.)
- **Epic Pass decision panel** — the panel is removed from Trips on
  both editions, along with its entry points (web: More › Passes &
  tickets; iOS: More › Passes & tickets) and its remembered
  expand/collapse state. The pass **engine** is unchanged: combined vs
  separate vs full, pro-rata shares, and the recommendation still land
  in each trip's Lift / Pass line.
- **Compare when empty** — on web the Compare tab/section no longer
  renders at all with zero picks (no heading, no empty state); it
  appears with the first pick. iOS keeps its permanent Compare tab
  with the minimal "Nothing here yet" state — an accepted platform
  difference, recorded in `docs/PARITY.md`.

### Coming-soon trip types removed

Beach, City break, Adventure and Family are gone from the catalog. The
only trip types are **Ski — West Coast** and **Ski — Japan** — both fully
priced. Removed with them: the type-picker "(coming soon)" labels, the
Explore "· Soon" filter chips and coming-soon placeholder card, and the
About line "Ski — West Coast & Ski — Japan pricing: Researched dataset ·
checked Nov 13, 2026. Other trip types are coming soon — no prices
invented." (Other provenance captions — the hotel "Price checked" line
and the flights snapshot note — stay.)

Graceful fallback: a saved trip or persisted gallery filter that still
names a removed type falls back to Ski — West Coast (web: state
normalization on load + engine fallback; iOS: `tripType(id:)` fallback
in PricingService + filter guard in Explore) instead of breaking or
dead-ending unpriced.

### Flight options replace the single basic/flex fare

Each destination/window no longer carries one `{basic, flex}` fare pair.
`flights` is now a Google-Flights-style block — a `note` plus `dec`/`jan`
arrays of **3 selectable options** (airline, fare class, round-trip price,
outbound + return times/durations/stops, Best/Cheapest tags). The researched
fares did not change: the option flagged `anchor` for each fare class *is*
the exact Nov 13, 2026 checked fare (SLC Dec JetBlue Basic $430.81 / Flex
$560.80; SLC Jan Delta Basic $458.80; RNO Dec Delta $608.40; RNO Jan Delta
$398.40; DEN Dec JetBlue $447.79; DEN Jan JetBlue $348.81; JAC Dec Delta
$540.41; JAC Jan American $483.40; CTS Jan American/JAL $1,228.19 with a
checked bag included; CTS Dec Lufthansa $5,268.29). Default selection =
the anchor for the trip's fare class, so every verified golden total
reproduces unchanged (default plan $3,112.43; Niseko Jan comfort $1,997.21).

Honesty note (also carried in each `flights.note`): the extra options are
representative of the same routes — real carriers for BOS–SLC/RNO/DEN/JAC/CTS
with realistic schedules (durations computed from the shown times) and prices
in the anchors' spread. They are a Nov 13, 2026 snapshot with representative
schedule examples, **not** a live timetable or live fares; the apps link out
to Google Flights for the real thing. `flightDetail` was removed — flight
summaries are now derived from the selected option.

### Photo cards: frosted glass (presentation, both apps)

Text that sits on destination photos (Explore cards, trip-card photo strips)
moved from the heavy dark scrim / solid plates to frosted-glass panels —
translucent black with backdrop blur and a hairline white border — and the
scrim was softened, so more of the photo shows through. No data change;
recorded here because the dataset package owns the design contract both
apps follow.

## Dataset v1 — 2026-11-13 (checkedAt: 2026-11-13)

Initial extraction of the web app's researched catalog
(`server/src/pricing.ts` in the Muse web prototype) into the shared package:
6 destinations (Park City, Tahoe–Heavenly, Alta/Snowbird, Jackson Hole,
Breckenridge, Niseko–Hirafu), 2 windows (Dec 19–23 2026, Jan 9–13 2027),
~30 hotels with tiers, tags and Expedia property IDs, the Epic Day Pass ladder
(only the 3-day $386 rung is exact; all other rungs are flagged estimates),
Jackson 3-of-4-day anchors ($782.58 Dec / $618.34 Jan) + single-day rates,
Niseko United anchors (Jan peak 3-day $255 / 4-day $335 at ¥155/$), Alta
per-day rates. Sources: Duffel (flights), Expedia (hotels), official resort
shops (lift). Flights are priced from Boston (BOS) only.

### Known reconciliation item — $1.66 (Park City, design mock)

The approved design document's Park City editor mock shows line items of
flight $560.80 (flex) + transfers $110.00 + Chateau Apres Lodge $883.48 +
Epic Day Pass share $128.67 + gear (rent) $153.00, which sum to **$1,835.95** —
**$1.66 more** than the web app's verified Park City total of **$1,834.29**.

Resolution: the mock's *lines* were illustrative; its *total* was the real
figure. The verified total decomposes exactly under the shipped engine as
basic fare $430.81 + transfers $110.00 + hotel $883.48 + combined-pass share
$320.00 (6-day pass $640 split pro-rata across two 3-day Epic trips) +
auto-selected gear (carry own skis) $90.00 = **$1,834.29**. The iOS pricing
goldens assert this computed-from-lines behaviour; no line was fudged to make
the mock's arithmetic agree. If the dataset is ever re-researched, re-check
this item first.

### Photos

`photoURL` is null for every destination in v1. The same six destination
photos ship **bundled** in the iOS app (copied from the web app's verified
assets, `client/src/assets/*.jpg`) and the app prefers a remote `photoURL`
whenever a future dataset sets one, falling back to the bundled photo and
then to the designed black gradient. Remote URLs land with the hosted
dataset refresh (v1.1) — they are a dataset edit, not a code change.
