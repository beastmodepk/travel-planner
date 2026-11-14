# Provider contracts — the portable backend boundary

Everything the UIs (web prototype, iOS app) know about prices and brochure
email comes through two contracts. Providers are interchangeable; no provider
internals leak past these shapes. This package is the definition of record —
the apps implement it, they don't redefine it.

- `pricing-request.schema.json` / `pricing-result.schema.json` — the
  `PricingProvider` payloads.
- `email-request.schema.json` / `email-result.schema.json` — the
  `EmailProvider` payloads.

## PricingProvider

```
id: String                      // "dataset" | "ai-research"
label: String                   // "Researched dataset"
isConfigured() -> Bool          // dataset: always true; ai-research: false until a backend exists
price(PricingRequest) async throws -> PricingResult
```

Ships today: **DatasetPricingProvider** (researched snapshot,
`packages/dataset/`, all maths on-device in the iOS app). Slot:
**AiResearchProvider** — returns an honest "not configured" and callers fall
back to the dataset silently. No vendor SDK, no API key, and no key-entry UI
exists in any client; when built, it will call our own backend, which holds
the key.

Semantics that are part of the contract:

- Amounts are **whole-party totals** (per-person figures already × travellers).
- Hotel prices are 4-night totals in the dataset; providers prorate by the
  trip's actual nights and flag the line as an estimate when they do.
- A line that cannot be priced is `null` + listed in `unpriced` — never
  silently zero, never invented.
- `estimate: true` renders as `~` in every UI.
- Pass programs (Epic) are returned per trip; the **plan-level** pass engine
  (combined vs separate vs full, pro-rata allocation, held pass = $0) runs on
  the results — see the iOS `PricingEngine.buildPassPlan`.

## EmailProvider

```
id: String                      // "queued-assistant" | "share-sheet"
send(EmailRequest) async throws -> EmailResult   // status: queued | sent | failed
```

Ships today: **QueuedEmailProvider** (records the brochure request locally —
recipient, subject, text, PDF file, timestamp, status "Queued for assistant")
and **ShareSheetEmailProvider** (hands the same payload to the system share
sheet / mail compose). Direct SMTP/Gmail sending is a server-side detail of a
future backend; credentials are deploy-time secrets (`.env.example`), never
client data.
