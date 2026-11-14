# Versioning & updates — Travel Planner (the house standard)

## The two numbers

Every iOS build carries **two** versions. They do different jobs:

| Number | Where users see it | Example | Who changes it |
|---|---|---|---|
| **Marketing version** (`MARKETING_VERSION`) | App Store page, Settings | `1.2.0` | A human, in the release PR |
| **Build number** (`CURRENT_PROJECT_VERSION`) | TestFlight list, App Store Connect | `214` | **CI only — never by hand** |

Apple's rules: a build number must be **strictly higher than every
previous upload** for that app, even for the same marketing version.
Reusing one is an automatic rejection at upload. That is why CI owns it.

## Marketing version = Semantic Versioning

`MAJOR.MINOR.PATCH`

- **PATCH** `1.2.0 → 1.2.1` — bug fixes only, no new behaviour.
- **MINOR** `1.2.0 → 1.3.0` — new features, old data and habits still work.
- **MAJOR** `1.x → 2.0.0` — big redesign, or a change that breaks old data/flows.

How a release happens:

1. Work lands on feature branches; PRs merge to `main` freely.
   Every merge to `main` uploads a **TestFlight** build automatically
   (build number = GitHub run × 10 + attempt, set by `release.yml`) and
   redeploys the **web edition** to GitHub Pages (`pages.yml`).
2. When a set of changes is worth shipping publicly, open a small release
   PR that only bumps `MARKETING_VERSION`, then tag that merge
   `v<version>` (e.g. `v1.3.0`). The tag build is the one you submit.
3. In App Store Connect, attach that build to the version, fill "What's
   New", and **Submit for Review**. Keep the final release manual (not
   automatic after approval) — one deliberate tap beats a surprise.
4. After approval, use **phased release** (Apple's default 7-day ramp:
   1% → 2% → 5% → 10% → 20% → 50% → 100% of users per day). You can pause
   the ramp for up to 30 days if crash reports or reviews go bad.

## How updates reach users

- **TestFlight testers** — get a push/email when a build finishes
  processing (~15–30 min after upload); they update inside the TestFlight
  app. Builds **expire after 90 days**. Internal testers (≤100) skip Beta
  App Review; external testers (≤10,000) need a light beta review per
  version.
- **App Store users** — iOS auto-updates apps when the user's "App
  Updates" setting is on (the default). A user can stay on an old version
  indefinitely — **we cannot force an update** from outside the app.
- **Web users** — always on the latest deploy; no version action needed.
- **No rollback.** Apple cannot un-ship a version. A bad release is fixed
  *forward*: ship a PATCH build, expedite review if it's urgent, and
  pause the phased ramp meanwhile. (Web can be rolled back by reverting
  the commit.)

## Designing so old versions survive

- Local data migrations must be **additive and backward-compatible** —
  never rename/delete stored fields in a way an older build would choke
  on. Test upgrading from the last App Store version.
- The shared dataset is versioned (`datasetVersion` in
  `packages/dataset/dataset.json`); both editions must tolerate a dataset
  one version older than themselves.
- Never change the CI build-number formula mid-stream; it is monotonic
  for the life of the repo.
