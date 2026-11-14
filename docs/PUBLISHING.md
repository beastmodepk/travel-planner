# Publishing Travel Planner — owner gates & runbook

Owner steps are Parthey's (Apple and GitHub require the account holder);
everything else is Alfred's. Status (2026-11-13): repo built locally with
the full pipeline wired — release workflow dry-runs unsigned until the
secrets below exist. **Nothing has been pushed yet** (deploy key not yet
registered on GitHub — step 1).

## 1. Push access — dedicated deploy key (Parthey adds the public key)

The repo `beastmodepk/travel-planner` already exists on GitHub. Pushes
from Alfred's VM use a **repo-scoped deploy key**, not a personal token:

- Private key (VM only, never leaves it): `~/.ssh/id_ed25519_travel_planner`
- Remote: `git@github-travel-planner:beastmodepk/travel-planner.git`
  (the `github-travel-planner` host alias resolves via `~/.ssh/config`
  to github.com with that identity file)
- **Parthey's step:** GitHub → repo → Settings → Deploy keys → Add deploy
  key → paste the **public** key (`~/.ssh/id_ed25519_travel_planner.pub`,
  Alfred supplies it on request) → tick **Allow write access** → Add key.
- Until that key is added, `git push` will fail with permission denied —
  expected, not a bug. Alfred does not push before Parthey confirms.

Note: deploy keys cannot add repo secrets or change repo settings —
steps 3–5 stay Parthey's in the GitHub UI.

## 2. App record in App Store Connect (Parthey, ~2 minutes)

App Store Connect → Apps → "+" → New App, with exactly:

- Platform: iOS
- Name: **Travel Planner** (if taken, Alfred suggests a variant first)
- Primary language: English (U.S.)
- Bundle ID: **com.parthey.travelplanner** (set in the Xcode project).
  If it is not in the dropdown yet, register it first at
  developer.apple.com → Certificates, Identifiers & Profiles →
  Identifiers → "+" → App IDs → App → description "Travel Planner",
  Bundle ID (Explicit): com.parthey.travelplanner, no capabilities
  needed → Register.
- SKU: `travelplanner-ios-001`
- User Access: Full Access

## 3. App Store Connect API key (Parthey creates, Alfred uses)

- App Store Connect → Users and Access → Integrations (API Keys) →
  Generate API Key
  - Name: `Alfred CI`
  - Access: **App Manager** (Admin also works and enables fully automatic signing)
- Note the **Key ID** and **Issuer ID** shown on that page.
- Download the `.p8` file (downloadable ONCE) and hand it to Alfred via
  Secure Vault — never chat, never email.

## 4. GitHub repo secrets (Parthey adds)

Repo → Settings → Secrets and variables → Actions → New repository secret:

- `ASC_KEY_ID` — from step 3
- `ASC_ISSUER_ID` — from step 3
- `ASC_KEY_P8` — full contents of the .p8 file
- `ASC_TEAM_ID` — developer.apple.com → Account → Membership details → Team ID

Once these exist, the next merge to `main` archives signed and uploads
to TestFlight automatically (`.github/workflows/release.yml`).

## 5. GitHub Pages — the web edition

- Workflow: `.github/workflows/pages.yml` deploys `apps/web` on every
  push to `main`.
- **Live URL: https://beastmodepk.github.io/travel-planner/**
- **If the first run reports "Pages not enabled"**: the owner enables it
  once — repo Settings → Pages → Build and deployment → Source:
  **"GitHub Actions"** — then re-run the workflow. Nothing in the repo
  can flip that setting itself.
- `apps/web` uses relative paths only, so it serves correctly from the
  `/travel-planner/` subpath.

## 6. Release flow (after the gates)

- Merge to `main` → TestFlight build (CI build number) + Pages deploy.
- Public release: bump `MARKETING_VERSION` in a release PR, tag `vX.Y.Z`,
  attach the build in App Store Connect, **Submit for Review stays
  Parthey's tap**. See `docs/VERSIONING.md`.
- Privacy: **Data Not Collected** (`docs/PRIVACY.md`); a hosted privacy
  URL can point at this repo's Pages site later if Apple asks for one.
