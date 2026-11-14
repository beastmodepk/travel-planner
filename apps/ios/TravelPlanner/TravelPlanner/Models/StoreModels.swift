import Foundation
import SwiftData

// Local-first store (SwiftData). Sync-ready by construction: every entity has
// a UUID and updatedAt, so the v2 shared backend can adopt these shapes
// without a remodel. View preferences deliberately do NOT live here — they
// are UserDefaults state (see ViewPrefs) and must never sync or reprice.

@Model
final class Profile {
    /// Singleton row — there is exactly one profile per device.
    @Attribute(.unique) var singletonKey: String = "profile"
    var name: String = ""
    var email: String = ""
    var homeAirport: String = "BOS"
    var levelRaw: String = SkiLevel.intermediate.rawValue
    var terrainRaw: [String] = [Terrain.mix.rawValue]
    var travelStyleRaw: String = TravelStylePref.balanced.rawValue
    var vibeRaw: String = Vibe.mix.rawValue
    var remoteWork: Bool = false
    var gearOwnedRaw: String = GearOwned.rent.rawValue
    var passHeldRaw: String = HeldPass.none.rawValue
    var groupRaw: String = GroupSize.solo.rawValue
    var onboarded: Bool = false
    var updatedAt: Date = Date()

    init() {}

    var level: SkiLevel {
        get { SkiLevel(rawValue: levelRaw) ?? .intermediate }
        set { levelRaw = newValue.rawValue }
    }
    var terrain: [Terrain] {
        get { terrainRaw.compactMap(Terrain.init(rawValue:)) }
        set { terrainRaw = newValue.map(\.rawValue) }
    }
    var travelStyle: TravelStylePref {
        get { TravelStylePref(rawValue: travelStyleRaw) ?? .balanced }
        set { travelStyleRaw = newValue.rawValue }
    }
    var vibe: Vibe {
        get { Vibe(rawValue: vibeRaw) ?? .mix }
        set { vibeRaw = newValue.rawValue }
    }
    var gearOwned: GearOwned {
        get { GearOwned(rawValue: gearOwnedRaw) ?? .rent }
        set { gearOwnedRaw = newValue.rawValue }
    }
    var passHeld: HeldPass {
        get { HeldPass(rawValue: passHeldRaw) ?? .none }
        set { passHeldRaw = newValue.rawValue }
    }
    var group: GroupSize {
        get { GroupSize(rawValue: groupRaw) ?? .solo }
        set { groupRaw = newValue.rawValue }
    }
}

/// Planner-wide settings (origin + travellers). Part of the store, per the
/// design's data model — unlike view prefs, these DO affect pricing.
@Model
final class PlannerSettings {
    @Attribute(.unique) var singletonKey: String = "settings"
    var origin: String = "BOS"
    var travellers: Int = 1
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class Trip {
    @Attribute(.unique) var id: UUID = UUID()
    /// Blank = the destination's name is used as the title.
    var title: String = ""
    var tripTypeID: String = "ski-west"
    /// Catalog destination id; nil for a user-added custom destination.
    var destinationID: String?
    var customDestinationName: String?
    var windowSelectionRaw: String = WindowSelection.dec.rawValue
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// Ski/activity days, 1–10.
    var activityDays: Int = 3
    var styleRaw: String = TripStyle.balanced.rawValue
    var fareClassRaw: String = FareClass.basic.rawValue
    /// Explicit flight pick (dataset flight-option id); "" = the anchor
    /// option for the fare class (the researched fare).
    var flightOptionID: String = ""
    var gearRaw: String = GearChoice.auto.rawValue
    var phaseRaw: String = TripPhase.plan.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \HotelVariant.trip)
    var hotelVariants: [HotelVariant] = []

    init() {}

    var windowSelection: WindowSelection {
        get { WindowSelection(rawValue: windowSelectionRaw) ?? .custom }
        set { windowSelectionRaw = newValue.rawValue }
    }
    var style: TripStyle {
        get { TripStyle(rawValue: styleRaw) ?? .balanced }
        set { styleRaw = newValue.rawValue }
    }
    var fareClass: FareClass {
        get { FareClass(rawValue: fareClassRaw) ?? .basic }
        set { fareClassRaw = newValue.rawValue }
    }
    var gear: GearChoice {
        get { GearChoice(rawValue: gearRaw) ?? .auto }
        set { gearRaw = newValue.rawValue }
    }
    var phase: TripPhase {
        get { TripPhase(rawValue: phaseRaw) ?? .plan }
        set { phaseRaw = newValue.rawValue }
    }
    var isCustomDestination: Bool { destinationID == nil }

    /// The Primary hotel selection — exactly one per trip; drives the total.
    var primaryVariant: HotelVariant? { hotelVariants.first(where: \.isPrimary) }    var selectedVariants: [HotelVariant] { hotelVariants.filter(\.isSelected) }

    func touch() { updatedAt = Date() }
}

/// Hotel selection state for one trip. Hotel *facts* (name, price, Expedia
/// ID) live in the dataset — a variant stores only tier + tags + selection,
/// so a dataset refresh re-prices existing trips correctly.
@Model
final class HotelVariant {
    @Attribute(.unique) var id: UUID = UUID()
    var tierRaw: String = HotelTier.comfort.rawValue
    var tags: [String] = []
    var isSelected: Bool = false
    var isPrimary: Bool = false
    var trip: Trip?

    init() {}

    var tier: HotelTier {
        get { HotelTier(rawValue: tierRaw) ?? .comfort }
        set { tierRaw = newValue.rawValue }
    }
}

/// An opt-in Compare entry. Stores references only (trip + variant tier) and
/// is always priced live — never a stored snapshot. Max 3, enforced by
/// CompareStore logic in the views layer.
@Model
final class ComparePick {
    @Attribute(.unique) var id: UUID = UUID()
    var tripID: UUID = UUID()
    var variantTierRaw: String = HotelTier.comfort.rawValue
    var addedAt: Date = Date()

    init() {}

    var variantTier: HotelTier {
        get { HotelTier(rawValue: variantTierRaw) ?? .comfort }
        set { variantTierRaw = newValue.rawValue }
    }
}

/// One queued brochure email. The PDF lives in Documents/Brochures as a file;
/// this row stores its filename, never a blob.
@Model
final class BrochureRequest {
    @Attribute(.unique) var id: UUID = UUID()
    var recipient: String = ""
    var subject: String = ""
    var summary: String = ""
    var emailText: String = ""
    var pdfFileName: String = ""
    var statusRaw: String = BrochureStatus.queued.rawValue
    var providerID: String = ""
    var tripTitle: String = ""
    var destinationName: String = ""
    var createdAt: Date = Date()
    var sentAt: Date?

    init() {}

    var status: BrochureStatus {
        get { BrochureStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }
}

/// A user-added destination (≤20, enforced at creation). Saved with dates and
/// style like any trip, but honestly unpriced until it joins the dataset.
@Model
final class CustomDestination {
    @Attribute(.unique) var id: String = ""
    var name: String = ""
    var createdAt: Date = Date()

    init() {}
}
