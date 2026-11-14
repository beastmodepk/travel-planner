import Foundation

/// A suggested phase move. Suggestions are only ever *offered* — phases move
/// when the user taps, never automatically (owner's rule).
struct PhaseSuggestion: Equatable {
    var target: TripPhase
    var message: String
}

enum PhaseLogic {
    /// Pure over primitives so it unit-tests without a store.
    /// - Past: trip ended before today and isn't already Past.
    /// - Enjoy: a Booked trip whose dates include today.
    static func suggestion(phase: TripPhase, start: Date, end: Date, today: Date) -> PhaseSuggestion? {
        let cal = Calendar(identifier: .gregorian)
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let todayDay = cal.startOfDay(for: today)
        if phase != .past && endDay < todayDay {
            let when = DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .none)
            return PhaseSuggestion(target: .past, message: "This trip ended \(when) — move it to Past trip?")
        }
        if phase == .book && startDay <= todayDay && todayDay <= endDay {
            return PhaseSuggestion(target: .enjoy, message: "You're on this trip — move it to Enjoy trip?")
        }
        return nil
    }

    static func suggestion(for trip: Trip, today: Date = Date()) -> PhaseSuggestion? {
        suggestion(phase: trip.phase, start: trip.startDate, end: trip.endDate, today: today)
    }
}
