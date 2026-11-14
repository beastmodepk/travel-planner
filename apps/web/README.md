# Travel Planner — Web

The web edition of Travel Planner (`apps/ios` is the iOS edition). Same
features, same dataset, same pricing semantics — see
[`docs/PARITY.md`](../../docs/PARITY.md) for the parity contract.

## Run it

It's a dependency-free static site — no build step:

```sh
cd apps/web
python3 -m http.server 8000
# open http://localhost:8000
```

All asset paths are relative, so it works from any subpath — deployed to
GitHub Pages at `https://beastmodepk.github.io/travel-planner/` by
`.github/workflows/pages.yml` (see `docs/PUBLISHING.md`).

## Files

| File | What |
|---|---|
| `index.html` | Shell (loads `engine.js` then `app.js`) |
| `styles.css` | Jet black #000 + white only; photos are the only colour |
| `engine.js` | Pricing engine — a 1:1 port of the iOS engine against the shared dataset (single-trip pricing, Epic Pass plan, price-from, style presets) |
| `app.js` | UI: onboarding, Explore, Trips + phases, editor, Epic Pass panel, opt-in Compare, brochure chooser + queue, Profile, Settings, About |
| `dataset.json` | Copy of `packages/dataset/dataset.json` — CI fails if the copies drift |

## State

Everything lives in the browser's `localStorage` (`tp-web-v1`): profile,
settings, trips, Compare picks, queued brochures, view prefs. Nothing is
sent anywhere; brochures queue locally as "Queued for assistant" exactly
as on iOS (PDF via print/save, text downloadable).

## Notes

- Destination photos load from remote URLs with a designed gradient
  fallback (the iOS app bundles the same six photos — see PARITY.md).
- Brochure "PDF" on web = the print stylesheet path (Print / save PDF);
  iOS generates a native PDF file. The brochure text is identical.
