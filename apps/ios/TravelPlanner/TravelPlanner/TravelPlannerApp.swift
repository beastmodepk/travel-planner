import SwiftUI
import SwiftData

@main
struct TravelPlannerApp: App {
    @State private var pricing: PricingService
    @State private var prefs = ViewPrefs()
    @State private var navigation = AppNavigation()
    @State private var brochures: BrochureService

    init() {
        // The bundled dataset is schema- and drift-checked in CI; if it ever
        // failed to decode we still open (with an empty catalog) rather than
        // crash — About & data sources surfaces the state.
        let catalog = (try? CatalogLoader.loadBundled()) ?? Catalog(
            datasetVersion: 0, checkedAt: "—", origin: "BOS", currency: "USD",
            tripTypes: [], windows: [], styles: [], epicPass: EpicPassProgram(
                program: "epic", name: "Epic", ladder: [], fullPassPrice: 1169,
                note: "", linkUrl: "https://www.epicpass.com", linkLabel: "Epic Pass"),
            nonEpicLift: NonEpicLiftTable(jackson: [:], niseko: [:], alta: NonEpicLiftTable.AltaRates(decPerDay: 0, janPerDay: 0)),
            carryBagFee: 90, destinations: [])
        let pricing = PricingService(catalog: catalog)
        _pricing = State(initialValue: pricing)
        _brochures = State(initialValue: BrochureService(catalog: catalog))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pricing)
                .environment(prefs)
                .environment(navigation)
                .environment(brochures)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [
            Profile.self, PlannerSettings.self, Trip.self, HotelVariant.self,
            ComparePick.self, BrochureRequest.self, CustomDestination.self,
        ])
    }
}

/// Cross-tab navigation state (tab selection, card highlight, editor
/// deep links from Explore).
@MainActor
@Observable
final class AppNavigation {
    enum Tab: Hashable {
        case explore, trips, compare, more
    }
    var selectedTab: Tab = .explore
    /// Trip card to ring-flash on arrival in the Trips tab.
    var highlightedTripID: UUID?
    /// Trip whose editor should open on arrival in the Trips tab.
    var editorTripID: UUID?

    func viewTrip(_ id: UUID) {
        highlightedTripID = id
        selectedTab = .trips
    }
    func editTrip(_ id: UUID) {
        editorTripID = id
        selectedTab = .trips
    }
}
