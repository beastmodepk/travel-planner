import SwiftUI
import SwiftData

/// Helpers for the opt-in Compare list: references only, priced live,
/// max 3 — nothing is ever added automatically.
enum CompareActions {
    static let maxPicks = 3

    static func isPicked(picks: [ComparePick], trip: Trip, tier: HotelTier) -> Bool {
        picks.contains { $0.tripID == trip.id && $0.variantTier == tier }
    }

    @discardableResult
    static func toggle(picks: [ComparePick], trip: Trip, tier: HotelTier, context: ModelContext) -> Bool {
        if let existing = picks.first(where: { $0.tripID == trip.id && $0.variantTier == tier }) {
            context.delete(existing)
            try? context.save()
            return false
        }
        guard picks.count < maxPicks else { return false }
        let pick = ComparePick()
        pick.tripID = trip.id
        pick.variantTier = tier
        context.insert(pick)
        try? context.save()
        return true
    }
}

/// Collapsed trip card: summary + total ONLY. The itemised breakdown lives
/// exclusively in the editor (owner's rule).
struct TripCardView: View {
    let trip: Trip
    let pricing: TripPricing?
    let catalog: Catalog
    var highlighted: Bool = false
    let onEdit: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var picks: [ComparePick]
    @State private var suggestionDismissed = false

    private var destName: String {
        trip.destinationID.flatMap { catalog.destination(id: $0)?.name }
            ?? trip.customDestinationName ?? "Trip"
    }
    private var displayTitle: String { trip.title.isEmpty ? destName : trip.title }
    private var destination: Destination? { trip.destinationID.flatMap { catalog.destination(id: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo strip with phase badge.
            ZStack(alignment: .bottomLeading) {
                DestinationPhoto(destination: destination, height: 110)
                HStack {
                    Badge(label: trip.phase.label, filled: true, onPhoto: true)
                    Spacer()
                    phaseMenu
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(displayTitle).font(.title3.bold()).lineLimit(2)
                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(TP.dim)
                if let flightSummary = pricing?.flightSummary, let flightAmount = pricing?.lines.first(where: { $0.key == "flight" })?.amount {
                    Text("\(flightSummary) · \(TP.money(flightAmount))")
                        .font(.caption)
                        .foregroundStyle(TP.faint)
                }

                if let suggestion = PhaseLogic.suggestion(for: trip), !suggestionDismissed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.message).font(.subheadline)
                        HStack(spacing: 16) {
                            Button("Move") {
                                trip.phase = suggestion.target
                                trip.touch()
                                try? context.save()
                            }
                            .font(.subheadline.bold())
                            .frame(minHeight: 44)
                            Button("Not now") { suggestionDismissed = true }
                                .font(.subheadline)
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(TP.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trip total").font(.caption).foregroundStyle(TP.faint)
                        if let total = pricing?.total {
                            Text(TP.money(total))
                                .font(.title2.bold())
                                .monospacedDigit()
                            if pricing?.partial == true {
                                Text("Partial — some lines not priced")
                                    .font(.caption).foregroundStyle(TP.faint)
                            }
                        } else {
                            Text("Not priced yet")
                                .font(.headline)
                                .foregroundStyle(TP.dim)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button("Edit details") { onEdit() }
                        .buttonStyle(SecondaryButtonStyle())
                    compareButton
                }
            }
            .padding(16)
        }
        .background(TP.black)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(highlighted ? TP.white : TP.separator, lineWidth: highlighted ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .swipeActions(edge: .leading) {
            Button("Edit details") { onEdit() }.tint(.white)
        }
    }

    private var metaLine: String {
        let dates = "\(PricingEngine.dateString(trip.startDate)) – \(PricingEngine.dateString(trip.endDate))"
        let style = catalog.style(id: trip.styleRaw)?.label ?? trip.styleRaw
        return "\(dates) · \(trip.activityDays) ski day\(trip.activityDays == 1 ? "" : "s") · \(style)"
    }

    private var phaseMenu: some View {
        Menu {
            ForEach(TripPhase.allCases) { phase in
                Button {
                    trip.phase = phase
                    trip.touch()
                    try? context.save()
                } label: {
                    Label(phase.label, systemImage: trip.phase == phase ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Move").font(.caption.bold())
                Image(systemName: "chevron.down").font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .foregroundStyle(TP.white)
            .glassPanel(cornerRadius: 22)
        }
        .accessibilityLabel("Move trip to another phase")
    }

    @ViewBuilder
    private var compareButton: some View {
        let primaryTier = trip.primaryVariant?.tier ?? .comfort
        let picked = CompareActions.isPicked(picks: picks, trip: trip, tier: primaryTier)
        if picked {
            Button("In Compare ✓") {
                _ = CompareActions.toggle(picks: picks, trip: trip, tier: primaryTier, context: context)
            }
            .buttonStyle(SecondaryButtonStyle())
        } else if picks.count >= CompareActions.maxPicks {
            Button("Compare is full (3 max)") {}
                .buttonStyle(SecondaryButtonStyle())
                .disabled(true)
                .opacity(0.45)
        } else {
            Button("Add to compare") {
                _ = CompareActions.toggle(picks: picks, trip: trip, tier: primaryTier, context: context)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}
