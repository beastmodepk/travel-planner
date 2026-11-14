import Foundation

/// Ships: serves the researched snapshot behind the contract. All maths is
/// on-device (PricingEngine), so the app prices fully offline.
struct DatasetPricingProvider: PricingProvider {
    let id = "dataset"
    let label = "Researched dataset"
    let catalog: Catalog

    func isConfigured() -> Bool { true }

    func price(_ request: PricingRequest) async -> PricingResult {
        PricingEngine.price(request, catalog: catalog)
    }
}

/// Slot only: no vendor SDK, no API key, no key-entry UI exists in the
/// client. When AI research ships, it calls our own backend (which holds the
/// key) and returns the same PricingResult shape; until then it reports
/// itself unconfigured and callers fall back to the dataset silently.
struct AiResearchProvider: PricingProvider {
    let id = "ai-research"
    let label = "AI research (not configured)"

    func isConfigured() -> Bool { false }

    func price(_ request: PricingRequest) async -> PricingResult {
        PricingResult(
            source: id, sourceLabel: label, checkedAt: "",
            priced: false, flight: nil, flightOptions: [], transfers: nil, hotelOptions: [], liftTicket: nil,
            passProgram: nil, passDays: request.skiDays, rentalPerDay: nil, gearOptions: [],
            chosenGearKey: nil, unpriced: ["provider"],
            notes: ["AI research is not configured in this build — showing the researched dataset instead."])
    }
}

/// Default email provider: records the request as a queued BrochureRequest
/// (the store write happens in BrochureService) for the assistant to send
/// from partheysmusebot@gmail.com. Queued is never dressed up as sent.
struct QueuedEmailProvider: EmailProvider {
    let id = "queued-assistant"
    let label = "Assistant mailbox"

    func send(_ request: EmailRequest) async -> EmailResult {
        EmailResult(
            status: .queued, provider: id, statusLabel: "Queued for assistant",
            detail: "Saved to the brochure queue. The assistant sends queued brochures from partheysmusebot@gmail.com.")
    }
}

/// Hands the brochure to the system share sheet / mail compose. The actual
/// presentation (and flipping the queue row to Sent on completion) happens
/// in the Brochures screen, which owns the UI; this provider exists so the
/// contract has both shipped implementations behind one interface.
struct ShareSheetEmailProvider: EmailProvider {
    let id = "share-sheet"
    let label = "Share sheet"

    func send(_ request: EmailRequest) async -> EmailResult {
        EmailResult(
            status: .queued, provider: id, statusLabel: "Ready to share",
            detail: "Open the brochure from the queue to share it or send it from your own mail app.")
    }
}
