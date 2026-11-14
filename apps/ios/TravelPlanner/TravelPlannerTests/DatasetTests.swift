import XCTest
@testable import TravelPlanner

/// The bundled dataset must decode and keep its researched anchors — the
/// same checks scripts/validate_dataset.py runs in CI, from inside the app.
final class DatasetTests: XCTestCase {
    func testBundledDatasetDecodes() throws {
        let catalog = try CatalogLoader.loadBundled()
        XCTAssertEqual(catalog.checkedAt, "2026-11-13")
        XCTAssertEqual(catalog.origin, "BOS")
        XCTAssertEqual(catalog.destinations.count, 6)
        XCTAssertEqual(Set(catalog.destinations.map(\.id)),
                       ["park-city", "tahoe", "alta", "jackson", "breckenridge", "niseko"])
    }

    func testEpicLadderSemantics() throws {
        let catalog = try CatalogLoader.loadBundled()
        let exact = catalog.epicPass.ladder.filter { !$0.estimate }
        XCTAssertEqual(exact.map(\.days), [3], "only the 3-day rung is exact")
        XCTAssertEqual(exact.first?.price, 386)
        XCTAssertEqual(catalog.epicPass.rung(days: 6)?.price, 640)
        XCTAssertEqual(catalog.epicPass.fullPassPrice, 1169)
    }

    func testGoldenAnchors() throws {
        let catalog = try CatalogLoader.loadBundled()
        let niseko = try XCTUnwrap(catalog.destination(id: "niseko"))
        let janComfort = niseko.hotel(window: "jan", tier: .comfort)
        XCTAssertEqual(janComfort?.name, "Torifito Hotel And Pod Niseko")
        XCTAssertEqual(janComfort?.price, 434.02)
        XCTAssertEqual(janComfort?.expediaId, "58975020")
        // The one known dataset gap: Niseko January premium books direct.
        let janPremium = niseko.hotel(window: "jan", tier: .premium)
        XCTAssertNil(janPremium?.name)
        XCTAssertNil(janPremium?.price)

        let parkCity = try XCTUnwrap(catalog.destination(id: "park-city"))
        let decComfort = parkCity.hotel(window: "dec", tier: .comfort)
        XCTAssertEqual(decComfort?.name, "Chateau Apres Lodge")
        XCTAssertEqual(decComfort?.price, 883.48)
        XCTAssertEqual(decComfort?.expediaId, "5692776")
    }

    func testFlightOptionAnchors() throws {
        let catalog = try CatalogLoader.loadBundled()
        // The anchor option of each fare class reproduces the researched
        // Nov 13, 2026 fare for the route/window exactly (Duffel).
        let expected: [String: [String: (Double, Double)]] = [
            "park-city": ["dec": (430.81, 560.80), "jan": (458.80, 628.80)],
            "alta": ["dec": (430.81, 560.80), "jan": (458.80, 628.80)],
            "tahoe": ["dec": (608.40, 738.40), "jan": (398.40, 528.41)],
            "jackson": ["dec": (540.41, 660.40), "jan": (483.40, 613.40)],
            "breckenridge": ["dec": (447.79, 547.80), "jan": (348.81, 448.80)],
            "niseko": ["dec": (5268.29, 5568.29), "jan": (1228.19, 1392.19)],
        ]
        for dest in catalog.destinations {
            XCTAssertFalse(dest.flights.note.isEmpty, "\(dest.id): flights snapshot note missing")
            for window in ["dec", "jan"] {
                let options = dest.flightOptions(window: window)
                XCTAssertEqual(options.count, 3, "\(dest.id)/\(window) should offer 3 flights")
                XCTAssertEqual(Set(options.map(\.id)).count, 3, "\(dest.id)/\(window) option ids must be unique")
                let basic = options.first { $0.anchor && $0.fareClass == "basic" }
                let flex = options.first { $0.anchor && $0.fareClass == "flex" }
                XCTAssertEqual(basic?.price, expected[dest.id]![window]!.0, "\(dest.id)/\(window) basic anchor")
                XCTAssertEqual(flex?.price, expected[dest.id]![window]!.1, "\(dest.id)/\(window) flex anchor")
            }
        }
        // The Jan Niseko anchor fare includes a checked bag (skis fly free).
        let niseko = try XCTUnwrap(catalog.destination(id: "niseko"))
        let janAnchor = niseko.flightOptions(window: "jan").first { $0.anchor && $0.fareClass == "basic" }
        XCTAssertEqual(janAnchor?.bagIncluded, true)
    }
}
