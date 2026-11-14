import XCTest
@testable import TravelPlanner

/// Pricing goldens: the web app's verified figures, reproduced from lines.
/// The web total for the default plan ($3,112.43) decomposes exactly under
/// this engine — see packages/dataset/CHANGELOG.md for the $1.66 design-mock
/// reconciliation note (the mock's illustrative lines summed to $1,835.95;
/// the verified total is what these tests assert).
final class PricingEngineTests: XCTestCase {
    private var catalog: Catalog!
    private var service: PricingService!

    override func setUpWithError() throws {
        catalog = try CatalogLoader.loadBundled()
        service = PricingService(catalog: catalog)
    }

    private func settings(origin: String = "BOS", travellers: Int = 1) -> PlannerSettings {
        let s = PlannerSettings()
        s.origin = origin
        s.travellers = travellers
        return s
    }

    private func makeTrips(_ drafts: [Seeding.TripDraft]) -> [Trip] {
        drafts.enumerated().map { Seeding.makeTrip(from: $1, catalog: catalog, sortIndex: $0) }
    }

    // MARK: Golden — default plan (web verified: $3,112.43)

    func testDefaultPlanGoldenTotals() throws {
        let trips = makeTrips(Seeding.defaultDrafts())
        let plan = service.plan(trips: trips, settings: settings(), profile: nil)
        let parkCity = try XCTUnwrap(plan.trips[trips[0].id])
        let tahoe = try XCTUnwrap(plan.trips[trips[1].id])
        XCTAssertEqual(parkCity.total ?? -1, 1834.29, accuracy: 0.001)
        XCTAssertEqual(tahoe.total ?? -1, 1278.14, accuracy: 0.001)
        XCTAssertEqual(plan.grandTotal ?? -1, 3112.43, accuracy: 0.001)
        XCTAssertFalse(plan.grandPartial)
    }

    func testDefaultPlanLineDecomposition() throws {
        // Park City Dec, Best Social: basic fare + transfers + Chateau Apres
        // + $320 combined-pass share + $90 auto gear (carry) = $1,834.29.
        let trips = makeTrips(Seeding.defaultDrafts())
        let plan = service.plan(trips: trips, settings: settings(), profile: nil)
        let pc = try XCTUnwrap(plan.trips[trips[0].id])
        let byKey = Dictionary(uniqueKeysWithValues: pc.lines.map { ($0.key, $0.amount ?? -1) })
        XCTAssertEqual(byKey["flight"] ?? -1, 430.81, accuracy: 0.001)
        XCTAssertEqual(byKey["transfers"] ?? -1, 110.00, accuracy: 0.001)
        XCTAssertEqual(byKey["hotel"] ?? -1, 883.48, accuracy: 0.001)
        XCTAssertEqual(byKey["lift"] ?? -1, 320.00, accuracy: 0.001)
        XCTAssertEqual(byKey["gear"] ?? -1, 90.00, accuracy: 0.001)
    }

    // MARK: Golden — Niseko Jan comfort ($1,997.21)

    func testNisekoJanComfortGolden() throws {
        let draft = Seeding.TripDraft(
            destinationID: "niseko", customName: nil, tripTypeID: "ski-japan",
            window: .jan, start: "2027-01-09", end: "2027-01-13", skiDays: 3,
            style: .balanced, fareClass: .basic, primaryTier: .comfort,
            selectedTiers: [.comfort], gear: .auto)
        let trips = makeTrips([draft])
        let plan = service.plan(trips: trips, settings: settings(), profile: nil)
        let niseko = try XCTUnwrap(plan.trips[trips[0].id])
        XCTAssertEqual(niseko.total ?? -1, 1997.21, accuracy: 0.001)
        // Gear: the Jan fare includes a checked bag, so carrying own skis is $0.
        let gear = niseko.lines.first { $0.key == "gear" }
        XCTAssertEqual(gear?.amount ?? -1, 0, accuracy: 0.001)
    }

    func testNisekoPriceFrom() {
        XCTAssertEqual(service.priceFrom(destinationID: "niseko", window: "jan") ?? -1, 1968.94, accuracy: 0.001)
    }

    // MARK: Epic Pass engine

    func testSixDayPassRecommendation() throws {
        let trips = makeTrips(Seeding.defaultDrafts())
        let plan = service.plan(trips: trips, settings: settings(), profile: nil)
        XCTAssertEqual(plan.pass.recommendedKey, "combined")
        let options = Dictionary(uniqueKeysWithValues: plan.pass.options.map { ($0.key, $0.amount) })
        XCTAssertEqual(options["combined"] ?? -1, 640, accuracy: 0.001)
        XCTAssertEqual(options["separate"] ?? -1, 772, accuracy: 0.001)
        XCTAssertEqual(options["full"] ?? -1, 1169, accuracy: 0.001)
        XCTAssertEqual(plan.pass.options.first { $0.key == "combined" }?.recommended, true)
    }

    func testPassSharesSumToPassCost() throws {
        let trips = makeTrips(Seeding.defaultDrafts())
        let results = trips.map { trip in
            PricingEngine.price(
                PricingRequest(
                    origin: "BOS", tripType: trip.tripTypeID, destinationId: trip.destinationID ?? "",
                    destinationName: "", custom: false,
                    departDate: PricingEngine.dateString(trip.startDate),
                    returnDate: PricingEngine.dateString(trip.endDate),
                    windowSelection: trip.windowSelection, skiDays: trip.activityDays,
                    travellers: 1, style: trip.style, fareClass: trip.fareClass,
                    hotelTier: .comfort, gear: .auto, heldPass: .none),
                catalog: catalog)
        }
        let pass = PricingEngine.buildPassPlan(results: results, travellers: 1, heldPass: .none)
        let shareSum = pass.shares.values.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(shareSum, 640, accuracy: 0.001)
    }

    func testPassAllocationUnevenDays() throws {
        // 3 + 4 Epic days → 7-day ladder rung $715; last trip takes the remainder.
        func result(days: Int) -> PricingResult {
            PricingEngine.price(
                PricingRequest(
                    origin: "BOS", tripType: "ski-west", destinationId: "park-city",
                    destinationName: "Park City", custom: false,
                    departDate: "2026-12-19", returnDate: "2026-12-23",
                    windowSelection: .dec, skiDays: days, travellers: 1,
                    style: .balanced, fareClass: .basic, hotelTier: .comfort,
                    gear: .auto, heldPass: .none),
                catalog: catalog)
        }
        let pass = PricingEngine.buildPassPlan(results: [result(days: 3), result(days: 4)], travellers: 1, heldPass: .none)
        XCTAssertEqual(pass.recommendedKey, "combined")
        XCTAssertEqual(pass.shares[0]?.amount ?? -1, 306.43, accuracy: 0.001)
        XCTAssertEqual(pass.shares[1]?.amount ?? -1, 408.57, accuracy: 0.001)
        XCTAssertEqual(pass.shares.values.reduce(0) { $0 + $1.amount }, 715, accuracy: 0.001)
    }

    func testHeldEpicPassZeroesShares() throws {
        let profile = Profile()
        profile.passHeld = .epic
        let trips = makeTrips(Seeding.defaultDrafts())
        let plan = service.plan(trips: trips, settings: settings(), profile: profile)
        XCTAssertEqual(plan.pass.recommendedKey, "held")
        XCTAssertEqual(plan.pass.options.first?.amount ?? -1, 0, accuracy: 0.001)
        for trip in trips {
            let lift = plan.trips[trip.id]?.lines.first { $0.key == "lift" }
            XCTAssertEqual(lift?.amount ?? -1, 0, accuracy: 0.001)
        }
    }

    func testHeldIkonZeroesJacksonLift() {
        let result = PricingEngine.price(
            PricingRequest(
                origin: "BOS", tripType: "ski-west", destinationId: "jackson",
                destinationName: "Jackson Hole", custom: false,
                departDate: "2027-01-09", returnDate: "2027-01-13",
                windowSelection: .jan, skiDays: 3, travellers: 1,
                style: .balanced, fareClass: .basic, hotelTier: .comfort,
                gear: .auto, heldPass: .ikon),
            catalog: catalog)
        XCTAssertEqual(result.liftTicket?.amount ?? -1, 0, accuracy: 0.001)
    }

    func testMoreThanTenPassDaysFallsToFullPass() {
        // Ladder tops out at 10 days; 11 combined days price at the full pass.
        func result(days: Int) -> PricingResult {
            PricingEngine.price(
                PricingRequest(
                    origin: "BOS", tripType: "ski-west", destinationId: "park-city",
                    destinationName: "Park City", custom: false,
                    departDate: "2026-12-19", returnDate: "2026-12-23",
                    windowSelection: .dec, skiDays: days, travellers: 1,
                    style: .balanced, fareClass: .basic, hotelTier: .comfort,
                    gear: .auto, heldPass: .none),
                catalog: catalog)
        }
        let pass = PricingEngine.buildPassPlan(results: [result(days: 6), result(days: 5)], travellers: 1, heldPass: .none)
        XCTAssertEqual(pass.options.first { $0.key == "combined" }?.amount ?? -1, 1169, accuracy: 0.001)
    }

    // MARK: Lift anchors

    func testJacksonFourDayJanTicket() {
        let jackson = catalog.destination(id: "jackson")!
        let lift = PricingEngine.nonEpicLift(dest: jackson, window: "jan", skiDays: 4, catalog: catalog)
        XCTAssertEqual(lift?.perPerson ?? -1, 835.30, accuracy: 0.001)
        XCTAssertEqual(lift?.estimate, false)
        let three = PricingEngine.nonEpicLift(dest: jackson, window: "jan", skiDays: 3, catalog: catalog)
        XCTAssertEqual(three?.perPerson ?? -1, 618.34, accuracy: 0.001)
    }

    // MARK: Gear

    func testGearAutoSelectExcludesPremium() {
        let result = PricingEngine.price(
            PricingRequest(
                origin: "BOS", tripType: "ski-west", destinationId: "park-city",
                destinationName: "Park City", custom: false,
                departDate: "2026-12-19", returnDate: "2026-12-23",
                windowSelection: .dec, skiDays: 3, travellers: 1,
                style: .balanced, fareClass: .basic, hotelTier: .comfort,
                gear: .auto, heldPass: .none),
            catalog: catalog)
        XCTAssertEqual(result.chosenGearKey, GearChoice.carry.rawValue)
        let premium = result.gearOptions.first { $0.key == GearChoice.premiumRent.rawValue }
        XCTAssertEqual(premium?.amount ?? -1, 213, accuracy: 0.001)  // $71/day × 3
    }

    // MARK: Honest unpriced paths

    func testNonBOSOriginLeavesFlightUnpriced() throws {
        let trips = makeTrips(Seeding.defaultDrafts())
        let plan = service.plan(trips: trips, settings: settings(origin: "JFK"), profile: nil)
        let pc = try XCTUnwrap(plan.trips[trips[0].id])
        XCTAssertTrue(pc.result.unpriced.contains("flight"))
        XCTAssertTrue(pc.partial)
        let flight = pc.lines.first { $0.key == "flight" }
        XCTAssertNil(flight?.amount)
    }

    func testCustomDestinationIsHonestlyUnpriced() {
        let result = PricingEngine.price(
            PricingRequest(
                origin: "BOS", tripType: "ski-west", destinationId: "Revelstoke",
                destinationName: "Revelstoke", custom: true,
                departDate: "2026-12-19", returnDate: "2026-12-23",
                windowSelection: .dec, skiDays: 3, travellers: 1,
                style: .balanced, fareClass: .basic, hotelTier: .comfort,
                gear: .auto, heldPass: .none),
            catalog: catalog)
        XCTAssertFalse(result.priced)
        XCTAssertTrue(result.unpriced.contains("destination"))
    }

    func testComingSoonTripTypeIsUnpriced() {
        let result = PricingEngine.price(
            PricingRequest(
                origin: "BOS", tripType: "beach", destinationId: "park-city",
                destinationName: "Park City", custom: false,
                departDate: "2026-12-19", returnDate: "2026-12-23",
                windowSelection: .dec, skiDays: 3, travellers: 1,
                style: .balanced, fareClass: .basic, hotelTier: .comfort,
                gear: .auto, heldPass: .none),
            catalog: catalog)
        XCTAssertFalse(result.priced)
        XCTAssertTrue(result.unpriced.contains("trip-type"))
    }

    // MARK: Cache discipline

    func testCacheKeyIgnoresViewState() {
        // PricingService.cacheKey takes only pricing inputs (trips/settings/
        // profile) — there is no view-pref parameter by construction. This
        // test pins that identical pricing inputs give identical keys.
        let trips = makeTrips(Seeding.defaultDrafts())
        let a = PricingService.cacheKey(trips: trips, settings: settings(), profile: nil, datasetVersion: 1)
        let b = PricingService.cacheKey(trips: trips, settings: settings(), profile: nil, datasetVersion: 1)
        XCTAssertEqual(a, b)
        let c = PricingService.cacheKey(trips: trips, settings: settings(travellers: 2), profile: nil, datasetVersion: 1)
        XCTAssertNotEqual(a, c)
    }
}
