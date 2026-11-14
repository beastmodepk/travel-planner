import Foundation

// Decodable mirror of packages/dataset/dataset.json — the single source of
// truth shared by web and iOS. The app bundles a copy (Resources/dataset.json,
// drift-checked in CI against the package); v1.1 refreshes it remotely.

struct Catalog: Decodable {
    let datasetVersion: Int
    let checkedAt: String
    let origin: String
    let currency: String
    let tripTypes: [TripTypeDef]
    let windows: [WindowDef]
    let styles: [StyleDef]
    let epicPass: EpicPassProgram
    let nonEpicLift: NonEpicLiftTable
    let carryBagFee: Double
    let destinations: [Destination]

    func destination(id: String) -> Destination? { destinations.first { $0.id == id } }
    func tripType(id: String) -> TripTypeDef { tripTypes.first { $0.id == id } ?? tripTypes[0] }
    func window(id: String) -> WindowDef? { windows.first { $0.id == id } }
    func style(id: String) -> StyleDef? { styles.first { $0.id == id } }
}

struct TripTypeDef: Decodable, Identifiable {
    let id: String
    let label: String
    let shortLabel: String
    let status: String  // "ready" — the catalog carries only priced types
    let blurb: String
}

struct WindowDef: Decodable, Identifiable {
    let id: String  // "dec" | "jan"
    let label: String
    let start: String  // yyyy-mm-dd
    let end: String
}

struct StyleDef: Decodable, Identifiable {
    let id: String
    let label: String
    let blurb: String
}

struct EpicPassProgram: Decodable {
    struct Rung: Decodable {
        let days: Int
        let price: Double
        let estimate: Bool
    }
    let program: String
    let name: String
    let ladder: [Rung]
    let fullPassPrice: Double
    let note: String
    let linkUrl: String
    let linkLabel: String

    func rung(days: Int) -> Rung? { ladder.first { $0.days == days } }
}

struct NonEpicLiftTable: Decodable {
    struct JacksonWindow: Decodable {
        let threeOfFour: Double
        let singleDay: Double
    }
    struct NisekoWindow: Decodable {
        let threeDay: Double
        let fourDay: Double
        let seasonNote: String
    }
    struct AltaRates: Decodable {
        let decPerDay: Double
        let janPerDay: Double
    }
    let jackson: [String: JacksonWindow]
    let niseko: [String: NisekoWindow]
    let alta: AltaRates
}

/// One leg of a flight option. Times are local to the departure/arrival
/// airports; arriveNextDay is how many calendar days later the arrival
/// falls (0, 1, or 2 for the long-haul Japan routings).
struct FlightLeg: Decodable {
    let depart: String  // "06:55"
    let arrive: String  // "10:45"
    let arriveNextDay: Int
    let duration: String  // "5h 50m"
    let stops: Int
    let via: String?
    var stopsLabel: String {
        if stops == 0 { return "Nonstop" }
        return "\(stops) stop\(stops == 1 ? "" : "s")\(via.map { " · \($0)" } ?? "")"
    }
    var stopsShort: String { stops == 0 ? "Nonstop" : "\(stops) stop\(stops == 1 ? "" : "s")" }
}

/// One selectable flight, Google-Flights style. `anchor` marks the exact
/// researched fare for its fare class — the default selection, so figures
/// verified against the Nov 13, 2026 research stay reproducible.
struct FlightOption: Decodable, Identifiable {
    let id: String
    let airline: String
    let fareClass: String  // "basic" | "flex"
    let price: Double      // per person, round trip
    let anchor: Bool
    let tags: [String]     // "best" | "cheapest"
    let bagIncluded: Bool?
    let outbound: FlightLeg
    let inbound: FlightLeg

    enum CodingKeys: String, CodingKey {
        case id, airline, fareClass, price, anchor, tags, bagIncluded, outbound
        case inbound = "return"
    }
}

/// The per-window option lists plus the snapshot honesty note.
struct FlightWindows: Decodable {
    let note: String
    let dec: [FlightOption]
    let jan: [FlightOption]
    func options(window: String) -> [FlightOption] { window == "jan" ? jan : dec }
}

struct HotelDef: Decodable {
    let name: String?
    let expediaId: String?
    /// Total for 4 nights incl. taxes/fees, 1 room. Null only with a null name.
    let price: Double?
    let tags: [String]
}

struct Destination: Decodable, Identifiable {
    let id: String
    let name: String
    let shortName: String
    let state: String
    let airport: String
    let region: String  // "west" | "japan"
    let tripTypeID: String
    let epic: Bool
    let socialScore: Int
    let snowScore: Int
    let tags: [String]
    let blurb: String
    let socialTier: HotelTier
    /// Round-trip airport transfers, per person.
    let transfers: Double
    let transfersDetail: String
    let flights: FlightWindows
    let hotels: [String: [String: HotelDef]]
    let rentalPerDay: Double
    let rentalEstimate: Bool
    let rentalName: String
    let rentalUrl: String
    let bootsPerDay: Double
    let bootsEstimate: Bool
    let ticketUrl: String
    let ticketLinkLabel: String
    let hotelSearchName: String
    /// Bundled asset-catalog image name.
    let photoAsset: String
    /// Remote photo for the hosted dataset (v1.1+); null in dataset v1.
    let photoURL: String?
    let photoAlt: String

    func hotel(window: String, tier: HotelTier) -> HotelDef? { hotels[window]?[tier.rawValue] }
    func flightOptions(window: String) -> [FlightOption] { flights.options(window: window) }
}

enum CatalogError: Error {
    case resourceMissing
    case decodeFailed(String)
}

enum CatalogLoader {
    /// Loads the bundled dataset. The decode is covered by unit tests; a
    /// failure here means a corrupt bundle, which CI's drift + schema checks
    /// are designed to catch before release.
    static func loadBundled(bundle: Bundle = .main) throws -> Catalog {
        guard let url = bundle.url(forResource: "dataset", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> Catalog {
        do {
            return try JSONDecoder().decode(Catalog.self, from: data)
        } catch {
            throw CatalogError.decodeFailed(String(describing: error))
        }
    }
}
