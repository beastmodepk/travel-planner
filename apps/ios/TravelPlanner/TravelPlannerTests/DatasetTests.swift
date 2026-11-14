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

    func testTripTypesReadyAndSoon() throws {
        let catalog = try CatalogLoader.loadBundled()
        XCTAssertEqual(catalog.tripType(id: "ski-west").status, "ready")
        XCTAssertEqual(catalog.tripType(id: "ski-japan").status, "ready")
        for soon in ["beach", "city", "adventure", "family"] {
            XCTAssertEqual(catalog.tripType(id: soon).status, "soon")
        }
    }
}
