import XCTest
@testable import TravelPlanner

/// Phase suggestions are offered, never applied automatically — these tests
/// pin the suggestion logic only.
final class PhaseLogicTests: XCTestCase {
    private func date(_ s: String) -> Date {
        PricingEngine.date(fromString: s)!
    }

    func testPastSuggestionAfterEndDate() {
        let s = PhaseLogic.suggestion(
            phase: .plan, start: date("2027-01-09"), end: date("2027-01-13"), today: date("2027-01-14"))
        XCTAssertEqual(s?.target, .past)
    }

    func testNoPastSuggestionOnEndDateItself() {
        let s = PhaseLogic.suggestion(
            phase: .enjoy, start: date("2027-01-09"), end: date("2027-01-13"), today: date("2027-01-13"))
        XCTAssertNil(s)
    }

    func testNoSuggestionWhenAlreadyPast() {
        let s = PhaseLogic.suggestion(
            phase: .past, start: date("2027-01-09"), end: date("2027-01-13"), today: date("2027-02-01"))
        XCTAssertNil(s)
    }

    func testEnjoySuggestionDuringBookedTrip() {
        let s = PhaseLogic.suggestion(
            phase: .book, start: date("2027-01-09"), end: date("2027-01-13"), today: date("2027-01-10"))
        XCTAssertEqual(s?.target, .enjoy)
    }

    func testNoEnjoySuggestionBeforeTripStarts() {
        let s = PhaseLogic.suggestion(
            phase: .book, start: date("2027-01-09"), end: date("2027-01-13"), today: date("2027-01-01"))
        XCTAssertNil(s)
    }

    func testNoSuggestionForFuturePlanTrip() {
        let s = PhaseLogic.suggestion(
            phase: .plan, start: date("2027-01-09"), end: date("2027-01-13"), today: date("2026-12-01"))
        XCTAssertNil(s)
    }
}
