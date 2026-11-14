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
    let status: String  // "ready" | "soon"
    let blurb: String
    var isReady: Bool { status == "ready" }
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

struct FarePair: Decodable {
    let basic: Double
    let flex: Double
    func fare(_ fareClass: FareClass) -> Double { fareClass == .flex ? flex : basic }
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
    let flights: [String: FarePair]
    let flightDetail: [String: String]
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
    func flight(window: String, fareClass: FareClass) -> Double? { flights[window]?.fare(fareClass) }
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
