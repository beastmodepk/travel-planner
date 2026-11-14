import Foundation
import SwiftData

/// First-run seeding + profile-derived defaults, mirroring the web app's
/// `defaultsFromProfile` / `applyStyle` (client/src/types.ts) exactly.
enum Seeding {

    static func defaultProfile() -> Profile {
        let p = Profile()
        p.name = ""
        p.email = ""
        p.homeAirport = "BOS"
        p.level = .intermediate
        p.terrain = [.mix]
        p.travelStyle = .balanced
        p.vibe = .mix
        p.remoteWork = false
        p.gearOwned = .rent
        p.passHeld = .none
        p.group = .solo
        p.onboarded = false
        return p
    }

    static func profileGear(_ p: Profile) -> GearChoice {
        switch p.gearOwned {
        case .ownSkis: return .carry
        case .ownBoots: return .boots
        case .rent: return .auto
        }
    }

    static func profileStyle(_ p: Profile) -> TripStyle {
        if p.vibe == .social { return .social }
        switch p.travelStyle {
        case .cheap: return .cheap
        case .treat: return .expensive
        case .balanced: return .balanced
        }
    }

    struct TripDraft {
        var destinationID: String?
        var customName: String?
        var tripTypeID: String
        var window: WindowSelection
        var start: String
        var end: String
        var skiDays: Int
        var style: TripStyle
        var fareClass: FareClass
        var primaryTier: HotelTier
        var selectedTiers: [HotelTier]
        var gear: GearChoice
    }

    /// Style presets set fare class, primary hotel tier, hotel selections
    /// and gear at once — the contract the editor captions.
    static func applyStyle(_ draft: TripDraft, style: TripStyle, socialTier: HotelTier, gearDefault: GearChoice) -> TripDraft {
        var d = draft
        d.style = style
        switch style {
        case .cheap:
            d.fareClass = .basic; d.primaryTier = .value; d.selectedTiers = [.value]; d.gear = gearDefault
        case .balanced:
            d.fareClass = .basic; d.primaryTier = .comfort; d.selectedTiers = [.comfort]; d.gear = gearDefault
        case .expensive:
            d.fareClass = .flex; d.primaryTier = .premium; d.selectedTiers = [.premium]; d.gear = .premiumRent
        case .social:
            d.fareClass = .basic; d.primaryTier = socialTier; d.selectedTiers = [socialTier]; d.gear = gearDefault
        case .snow:
            d.fareClass = .basic; d.primaryTier = .comfort; d.selectedTiers = [.comfort]; d.gear = gearDefault
        }
        return d
    }

    /// The two trips seeded from a completed onboarding (web parity).
    static func draftsFromProfile(_ p: Profile, catalog: Catalog) -> [TripDraft] {
        let gear = profileGear(p)
        let style = profileStyle(p)
        let parkCity = catalog.destination(id: "park-city")
        let tahoe = catalog.destination(id: "tahoe")
        let base1 = TripDraft(
            destinationID: "park-city", customName: nil, tripTypeID: "ski-west",
            window: .dec, start: "2026-12-19", end: "2026-12-23", skiDays: 3,
            style: style, fareClass: .basic, primaryTier: .comfort, selectedTiers: [.comfort], gear: gear)
        let trip1 = applyStyle(base1, style: style, socialTier: parkCity?.socialTier ?? .comfort, gearDefault: gear)
        let style2: TripStyle = style == .cheap ? .balanced : .cheap
        let base2 = TripDraft(
            destinationID: "tahoe", customName: nil, tripTypeID: "ski-west",
            window: .jan, start: "2027-01-09", end: "2027-01-13", skiDays: 3,
            style: style2, fareClass: .basic, primaryTier: .value, selectedTiers: [.value], gear: gear)
        let trip2 = applyStyle(base2, style: style2, socialTier: tahoe?.socialTier ?? .premium, gearDefault: gear)
        return [trip1, trip2]
    }

    /// The web's default plan, used when onboarding is skipped.
    static func defaultDrafts() -> [TripDraft] {
        [
            TripDraft(destinationID: "park-city", customName: nil, tripTypeID: "ski-west",
                      window: .dec, start: "2026-12-19", end: "2026-12-23", skiDays: 3,
                      style: .social, fareClass: .basic, primaryTier: .comfort, selectedTiers: [.comfort], gear: .auto),
            TripDraft(destinationID: "tahoe", customName: nil, tripTypeID: "ski-west",
                      window: .jan, start: "2027-01-09", end: "2027-01-13", skiDays: 3,
                      style: .cheap, fareClass: .basic, primaryTier: .value, selectedTiers: [.value], gear: .auto),
        ]
    }

    static func makeTrip(from draft: TripDraft, catalog: Catalog, sortIndex: Int) -> Trip {
        let trip = Trip()
        trip.title = ""
        trip.tripTypeID = draft.tripTypeID
        trip.destinationID = draft.destinationID
        trip.customDestinationName = draft.customName
        trip.windowSelection = draft.window
        trip.startDate = PricingEngine.date(fromString: draft.start) ?? Date()
        trip.endDate = PricingEngine.date(fromString: draft.end) ?? Date()
        trip.activityDays = draft.skiDays
        trip.style = draft.style
        trip.fareClass = draft.fareClass
        trip.gear = draft.gear
        trip.phase = .plan
        trip.sortIndex = sortIndex
        trip.hotelVariants = HotelTier.allCases.map { tier in
            let v = HotelVariant()
            v.tier = tier
            v.tags = tags(for: draft, tier: tier, catalog: catalog)
            v.isSelected = draft.selectedTiers.contains(tier)
            v.isPrimary = tier == draft.primaryTier
            v.trip = trip
            return v
        }
        return trip
    }

    private static func tags(for draft: TripDraft, tier: HotelTier, catalog: Catalog) -> [String] {
        guard let id = draft.destinationID, let dest = catalog.destination(id: id) else { return [] }
        let window = draft.window == .custom
            ? PricingEngine.resolveWindow(selection: .custom, start: draft.start, end: draft.end, catalog: catalog).window
            : draft.window.rawValue
        return dest.hotel(window: window, tier: tier)?.tags ?? []
    }

    /// Refresh a trip's variant tags after its window/destination changes —
    /// facts come from the dataset; selections and Primary are preserved.
    static func refreshVariantTags(for trip: Trip, catalog: Catalog) {
        guard let id = trip.destinationID, let dest = catalog.destination(id: id) else { return }
        let (window, _) = PricingEngine.resolveWindow(
            selection: trip.windowSelection,
            start: PricingEngine.dateString(trip.startDate),
            end: PricingEngine.dateString(trip.endDate), catalog: catalog)
        for variant in trip.hotelVariants {
            variant.tags = dest.hotel(window: window, tier: variant.tier)?.tags ?? []
        }
    }

    /// Inserts profile + settings + trips on first run. Idempotent: does
    /// nothing when a profile already exists.
    static func seedIfNeeded(context: ModelContext, catalog: Catalog, profile: Profile?, skipped: Bool) {
        let existing = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        guard existing.isEmpty else { return }

        let p = profile ?? defaultProfile()
        p.onboarded = true
        context.insert(p)

        let settings = PlannerSettings()
        settings.origin = p.homeAirport.uppercased().isEmpty ? "BOS" : p.homeAirport.uppercased()
        settings.travellers = skipped && profile == nil ? 1 : p.group.travellers
        context.insert(settings)

        let drafts = profile != nil ? draftsFromProfile(p, catalog: catalog) : defaultDrafts()
        for (i, draft) in drafts.enumerated() {
            context.insert(makeTrip(from: draft, catalog: catalog, sortIndex: i))
        }
        try? context.save()
    }
}
