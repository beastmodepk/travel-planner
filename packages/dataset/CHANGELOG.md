# Dataset changelog

All price changes to `dataset.json` land here, newest first. Prices change by
editing this package — never by editing app code.

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
