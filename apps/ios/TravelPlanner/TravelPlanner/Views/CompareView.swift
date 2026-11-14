import SwiftUI
import SwiftData

/// Opt-in comparison. Starts empty and stays empty until the user adds a
/// listing — nothing ever auto-populates. Cheapest in each row flips to a
/// white cell with black bold text and a LOWEST tag (the only inverted
/// cells in the app). Picks persist and always price live.
struct CompareView: View {
    @Environment(PricingService.self) private var pricing
    @Environment(\.modelContext) private var context
    @Query(sort: \ComparePick.addedAt) private var picks: [ComparePick]
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]

    private struct Column {
        var pick: ComparePick
        var trip: Trip
        var variant: VariantPricing
        var title: String
    }

    private var columns: [Column] {
        let plan = pricing.plan(trips: trips, settings: settingsRows.first, profile: profiles.first)
        return picks.compactMap { pick in
            guard let trip = trips.first(where: { $0.id == pick.tripID }),
                  let variant = plan.trips[trip.id]?.variants.first(where: { $0.tier == pick.variantTier })
            else { return nil }
            let dest = trip.destinationID.flatMap { pricing.catalog.destination(id: $0)?.shortName }
                ?? trip.customDestinationName ?? trip.title
            return Column(pick: pick, trip: trip, variant: variant, title: "\(dest) · \(variant.hotelName)")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if columns.isEmpty {
                        emptyState
                    } else {
                        chipsRow
                        table
                        Text("White cell marked LOWEST = cheapest in that row. Nothing is compared until you add it.")
                            .font(.caption)
                            .foregroundStyle(TP.faint)
                        if columns.count == 1 {
                            Text("Add a second listing to see LOWEST markers.")
                                .font(.caption)
                                .foregroundStyle(TP.faint)
                        }
                    }
                }
                .padding(16)
            }
            .tpBackground()
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 40))
                .foregroundStyle(TP.faint)
            Text("Nothing here yet")
                .font(.title3.bold())
            Text("Tap Add to compare on any listing to line it up here.")
                .font(.subheadline)
                .foregroundStyle(TP.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
        .padding(.top, 24)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(columns, id: \.pick.id) { column in
                    Button {
                        context.delete(column.pick)
                        try? context.save()
                    } label: {
                        HStack(spacing: 6) {
                            Text(column.title).lineLimit(1)
                            Image(systemName: "xmark").font(.caption.bold())
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .overlay(Capsule().stroke(TP.hairline, lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(column.title) from compare")
                }
                Button("Clear all") {
                    picks.forEach { context.delete($0) }
                    try? context.save()
                }
                .font(.subheadline)
                .underline()
                .frame(minHeight: 44)
            }
        }
    }

    private struct Row {
        var label: String
        var values: ([Column]) -> (amount: Double?, estimate: Bool)
    }

    private var rows: [Row] {
        [
            Row(label: "Flight") { ($0.variant.flightAmount, $0.variant.flightEstimate) },
            Row(label: "Transfers") { ($0.variant.transfersAmount, $0.variant.transfersEstimate) },
            Row(label: "Hotel") { ($0.variant.hotelAmount, $0.variant.hotelEstimate) },
            Row(label: "Lift / Pass") { ($0.variant.liftAmount, $0.variant.liftEstimate) },
            Row(label: "Gear") { ($0.variant.gearAmount, $0.variant.gearEstimate) },
            Row(label: "Total") { ($0.variant.total, $0.variant.partial) },
        ]
    }

    private var table: some View {
        VStack(spacing: 0) {
            // Header: hotel names.
            HStack(spacing: 0) {
                Text("").frame(width: 74, alignment: .leading)
                ForEach(columns, id: \.pick.id) { column in
                    Text(column.variant.hotelName)
                        .font(.caption.bold)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 8)
            Divider().background(TP.hairline)

            ForEach(rows, id: \.label) { row in
                let amounts = columns.map { row.values($0).amount }
                let minAmount = amounts.compactMap { $0 }.min()
                HStack(spacing: 0) {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(TP.dim)
                        .frame(width: 74, alignment: .leading)
                    ForEach(Array(columns.enumerated()), id: \.element.pick.id) { _, column in
                        let value = row.values(column)
                        let isLowest = columns.count > 1 && value.amount != nil && value.amount == minAmount
                        VStack(spacing: 2) {
                            Text(TP.money(value.amount) + (value.estimate && row.label != "Total" ? " ~" : ""))
                                .font(row.label == "Total" ? .body.bold() : .subheadline)
                                .monospacedDigit()
                            if isLowest {
                                Text("LOWEST")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .tracking(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 7)
                        .background(isLowest ? TP.white : Color.clear)
                        .foregroundStyle(isLowest ? TP.black : TP.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel(isLowest ? "\(TP.money(value.amount)), lowest in row" : TP.money(value.amount))
                    }
                }
                .padding(.vertical, 2)
                Divider().background(TP.separator)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.separator, lineWidth: 1))
    }
}
