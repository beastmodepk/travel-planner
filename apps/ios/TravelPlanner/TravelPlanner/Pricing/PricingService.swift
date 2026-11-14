import Foundation
import Observation

/// One trip's assembled pricing: contract result + display lines + variants.
struct TripPricing {
    var result: PricingResult
    /// Itemised lines — shown ONLY inside the trip editor (owner's rule).
    var lines: [PricedOption]
    /// Chosen flight's one-line summary (airline + outbound times + stops)
    /// for the trip card; nil when flights aren't priced.
    var flightSummary: String?
    var total: Double?
    var partial: Bool
    var variants: [VariantPricing]
    var warnings: [String]
}

/// A trip × hotel-tier variant — the unit Compare and the brochure chooser
/// work with. Category amounts are kept separate so Compare can mark the
/// cheapest in each row.
struct VariantPricing: Identifiable {
    var tier: HotelTier
    var hotelName: String
    var hotelTags: [String]
    var isPrimary: Bool
    var flightAmount: Double?
    var flightEstimate: Bool
    var transfersAmount: Double?
    var transfersEstimate: Bool
    var hotelAmount: Double?
    var hotelEstimate: Bool
    var liftAmount: Double?
    var liftEstimate: Bool
    var liftLabel: String
    var gearAmount: Double?
    var gearEstimate: Bool
    var total: Double?
    var partial: Bool
    var id: String { tier.rawValue }
}

struct PlanPricing {
    var trips: [UUID: TripPricing]
    var pass: PricingEngine.PassPlan
    var grandTotal: Double?
    var grandPartial: Bool
}

/// Prices the whole plan through the provider contracts and memoises per
/// configuration hash. View-only state (sort, filter, phase tab) is never an
/// input, so it can never invalidate pricing — a deliberate web behaviour.
@MainActor
@Observable
final class PricingService {
    let catalog: Catalog
    private let providers: [any PricingProvider]
    private var cache: [String: PlanPricing] = [:]

    init(catalog: Catalog) {
        self.catalog = catalog
        // AI research first when configured; dataset always available as the
        // silent fallback. Order matters; isConfigured() decides.
        self.providers = [AiResearchProvider(), DatasetPricingProvider(catalog: catalog)]
    }

    /// Cache key over pricing inputs only. Exposed for tests: two plans that
    /// differ only in view prefs produce the same key.
    static func cacheKey(trips: [Trip], settings: PlannerSettings?, profile: Profile?, datasetVersion: Int) -> String {
        var parts: [String] = ["v\(datasetVersion)"]
        parts.append("origin=\(settings?.origin ?? "BOS")")
        parts.append("trav=\(settings?.travellers ?? 1)")
        parts.append("held=\(profile?.passHeld.rawValue ?? "none")")
        for trip in trips {
            parts.append([
                trip.id.uuidString, trip.tripTypeID, trip.destinationID ?? "custom:\(trip.customDestinationName ?? "")",
                PricingEngine.dateString(trip.startDate), PricingEngine.dateString(trip.endDate),
                trip.windowSelectionRaw, String(trip.activityDays), trip.styleRaw, trip.fareClassRaw,
                trip.flightOptionID, trip.gearRaw, trip.primaryVariant?.tierRaw ?? "-",
            ].joined(separator: "|"))
        }
        return parts.joined(separator: ";")
    }

    func plan(trips: [Trip], settings: PlannerSettings?, profile: Profile?) -> PlanPricing {
        let key = Self.cacheKey(trips: trips, settings: settings, profile: profile, datasetVersion: catalog.datasetVersion)
        if let cached = cache[key] { return cached }
        let computed = computePlan(trips: trips, settings: settings, profile: profile)
        cache[key] = computed
        return computed
    }

    func priceFrom(destinationID: String, window: String) -> Double? {
        guard let dest = catalog.destination(id: destinationID) else { return nil }
        return PricingEngine.priceFrom(dest: dest, window: window, catalog: catalog)
    }

    // MARK: - Assembly

    private func request(for trip: Trip, settings: PlannerSettings?, profile: Profile?) -> PricingRequest {
        let destName: String
        if let id = trip.destinationID {
            destName = catalog.destination(id: id)?.name ?? id
        } else {
            destName = trip.customDestinationName ?? ""
        }
        // A saved trip may carry a tripTypeID the catalog no longer has
        // (Beach / City break / Adventure / Family were removed). tripType(id:)
        // falls back to the first catalog type — Ski — West Coast — so the
        // trip keeps pricing instead of breaking.
        let effectiveTypeID = catalog.tripType(id: trip.tripTypeID).id
        let readyType = effectiveTypeID == "ski-west" || effectiveTypeID == "ski-japan"
        return PricingRequest(
            origin: (settings?.origin ?? "BOS").uppercased(),
            tripType: effectiveTypeID,
            destinationId: trip.destinationID ?? destName,
            destinationName: destName,
            custom: trip.destinationID == nil || !readyType,
            departDate: PricingEngine.dateString(trip.startDate),
            returnDate: PricingEngine.dateString(trip.endDate),
            windowSelection: trip.windowSelection,
            skiDays: trip.activityDays,
            travellers: settings?.travellers ?? 1,
            style: trip.style,
            fareClass: trip.fareClass,
            flightOptionId: trip.flightOptionID.isEmpty ? nil : trip.flightOptionID,
            hotelTier: trip.primaryVariant?.tier ?? .comfort,
            gear: trip.gear,
            heldPass: profile?.passHeld ?? .none)
    }

    private func computePlan(trips: [Trip], settings: PlannerSettings?, profile: Profile?) -> PlanPricing {
        let travellers = settings?.travellers ?? 1
        let results = trips.map { trip in
            let req = request(for: trip, settings: settings, profile: profile)
            // Providers are synchronous maths behind an async contract; the
            // dataset provider always answers, so a semaphore-free direct
            // call through the engine keeps this deterministic and testable.
            return PricingEngine.price(req, catalog: catalog)
        }
        let pass = PricingEngine.buildPassPlan(results: results, travellers: travellers, heldPass: profile?.passHeld ?? .none)

        var priced: [UUID: TripPricing] = [:]
        for (i, trip) in trips.enumerated() {
            let r = results[i]
            guard r.priced else {
                priced[trip.id] = TripPricing(
                    result: r, lines: [], flightSummary: nil, total: nil, partial: true, variants: [], warnings: [])
                continue
            }
            var lines: [PricedOption] = []
            if let flight = r.flight {
                lines.append(flight)
            } else if r.unpriced.contains("flight") {
                lines.append(PricedOption(
                    key: "flight", label: "Flight",
                    detail: "Not priced for departures from \((settings?.origin ?? "BOS").uppercased()) in this source",
                    amount: nil, estimate: false, linkUrl: nil, linkLabel: nil))
            }
            if let transfers = r.transfers { lines.append(transfers) }
            let primaryTier = trip.primaryVariant?.tier ?? .comfort
            if let hotel = r.hotelOptions.first(where: { $0.key == primaryTier.rawValue }) ?? r.hotelOptions.first {
                lines.append(PricedOption(
                    key: "hotel", label: "Hotel · \(hotel.label)", detail: hotel.detail,
                    amount: hotel.amount, estimate: hotel.estimate,
                    linkUrl: hotel.linkUrl, linkLabel: hotel.linkLabel, tags: hotel.tags))
            }
            if let lift = r.liftTicket { lines.append(lift) }
            if let share = pass.shares[i] {
                lines.append(PricedOption(
                    key: "lift", label: share.label, detail: share.detail,
                    amount: share.amount, estimate: share.estimate,
                    linkUrl: share.linkUrl, linkLabel: share.linkLabel))
            }
            if let key = r.chosenGearKey, let gear = r.gearOptions.first(where: { $0.key == key }) {
                lines.append(PricedOption(
                    key: "gear", label: "Gear · \(gear.label)", detail: gear.detail,
                    amount: gear.amount, estimate: gear.estimate,
                    linkUrl: gear.linkUrl, linkLabel: gear.linkLabel))
            }

            var warnings: [String] = []
            let hotel = r.hotelOptions.first(where: { $0.key == primaryTier.rawValue })
            if profile?.remoteWork == true, let name = hotel?.label, name.lowercased().contains("hostel") {
                warnings.append("You work remotely on trips — a hostel pod won't give you a proper room and wifi for workdays. Pick a comfort or premium hotel.")
            }
            if let p = profile, (p.level == .beginner || p.level == .firstTime),
               trip.destinationID == "alta" || trip.destinationID == "jackson" {
                warnings.append("Steep learning curve here for a new skier — Park City, Tahoe and Breckenridge have gentler terrain to learn on.")
            }

            let total = PricingEngine.round2(lines.reduce(0) { $0 + ($1.amount ?? 0) })
            let partial = lines.contains { $0.amount == nil } || !r.unpriced.isEmpty

            let flightLine = lines.first { $0.key == "flight" }
            let transfersLine = lines.first { $0.key == "transfers" }
            let liftLine = lines.first { $0.key == "lift" }
            let gearLine = lines.first { $0.key == "gear" }
            let variants: [VariantPricing] = r.hotelOptions.map { h in
                let tier = HotelTier(rawValue: h.key) ?? .comfort
                let amounts: [Double?] = [flightLine?.amount, transfersLine?.amount, h.amount, liftLine?.amount, gearLine?.amount]
                return VariantPricing(
                    tier: tier, hotelName: h.label, hotelTags: h.tags,
                    isPrimary: tier == primaryTier,
                    flightAmount: flightLine?.amount, flightEstimate: flightLine?.estimate ?? false,
                    transfersAmount: transfersLine?.amount, transfersEstimate: transfersLine?.estimate ?? false,
                    hotelAmount: h.amount, hotelEstimate: h.estimate,
                    liftAmount: liftLine?.amount, liftEstimate: liftLine?.estimate ?? false,
                    liftLabel: liftLine?.label ?? "Lift / Pass",
                    gearAmount: gearLine?.amount, gearEstimate: gearLine?.estimate ?? false,
                    total: h.amount == nil ? nil : PricingEngine.round2(amounts.reduce(0) { $0 + ($1 ?? 0) }),
                    partial: amounts.contains { $0 == nil })
            }

            priced[trip.id] = TripPricing(
                result: r, lines: lines,
                flightSummary: r.flightOptions.first(where: \.selected)?.summary,
                total: r.priced ? total : nil, partial: partial,
                variants: variants, warnings: warnings)
        }

        let totals = trips.compactMap { priced[$0.id]?.total }
        return PlanPricing(
            trips: priced, pass: pass,
            grandTotal: totals.isEmpty ? nil : PricingEngine.round2(totals.reduce(0, +)),
            grandPartial: trips.contains { priced[$0.id]?.partial ?? true })
    }
}
