import Foundation

// Swift mirror of packages/contracts — the portable backend boundary.
// Providers are interchangeable: DatasetPricingProvider serves the researched
// snapshot; AiResearchProvider is the slot where a live model attaches later
// (via our own backend — a key never lives in this client).

struct PricingRequest {
    /// Origin airport code, e.g. "BOS". A user setting — never hardcoded.
    var origin: String
    var tripType: String
    /// Catalog destination id, or a user-added resort name when custom.
    var destinationId: String
    var destinationName: String
    var custom: Bool
    var departDate: String  // yyyy-mm-dd
    var returnDate: String  // yyyy-mm-dd
    var windowSelection: WindowSelection
    var skiDays: Int
    var travellers: Int
    var style: TripStyle
    var fareClass: FareClass
    var hotelTier: HotelTier
    var gear: GearChoice
    /// Pass the traveller already holds — providers zero covered lift costs.
    var heldPass: HeldPass
}

struct PricedOption: Identifiable {
    var key: String
    var label: String
    var detail: String
    /// Total for the whole party (per-person items already × travellers).
    /// Null only for a hotel tier with no property in the dataset.
    var amount: Double?
    var estimate: Bool
    var linkUrl: String?
    var linkLabel: String?
    /// Hotel candidate tags (hotel options only).
    var tags: [String] = []
    var id: String { key }
}

/// A multi-day pass program a provider can offer (Epic), priced per person.
struct PassProgram {
    var program: String  // "epic"
    var name: String     // "Epic"
    var dayPassLadder: [(days: Int, pricePerPerson: Double, estimate: Bool)]
    var fullPassPricePerPerson: Double
    var note: String
    var linkUrl: String
    var linkLabel: String
}

struct PricingResult {
    var source: String       // "dataset" | "ai-research"
    var sourceLabel: String  // "Researched dataset"
    var checkedAt: String    // "2026-11-13"
    var priced: Bool
    var flight: PricedOption?
    var transfers: PricedOption?
    var hotelOptions: [PricedOption]
    var liftTicket: PricedOption?
    var passProgram: PassProgram?
    var passDays: Int
    var rentalPerDay: Double?
    var gearOptions: [PricedOption]
    var chosenGearKey: String?
    /// Line keys that could not be priced, e.g. ["flight"] or ["destination"].
    var unpriced: [String]
    var notes: [String]
}

protocol PricingProvider {
    var id: String { get }
    var label: String { get }
    func isConfigured() -> Bool
    func price(_ request: PricingRequest) async -> PricingResult
}

// MARK: - Email contract

struct EmailRequest {
    var to: String
    var subject: String
    var textBody: String
    /// The brochure PDF as a file (Documents/Brochures) — never a DB blob.
    var pdfFileURL: URL
    var pdfFilename: String
    /// One-line plan summary, stored with the request for the queue list.
    var planSummary: String
}

struct EmailResult {
    enum Status: String {
        case queued, sent, failed
    }
    var status: Status
    var provider: String
    var statusLabel: String
    var detail: String
}

protocol EmailProvider {
    var id: String { get }
    var label: String { get }
    func send(_ request: EmailRequest) async -> EmailResult
}
