import SwiftUI
import SwiftData

/// Brochure chooser: every priced variant (trip × hotel), primaries
/// pre-ticked, unpriced variants disabled with the reason. The button is
/// never disabled by a repricing refresh; errors surface in-sheet; the done
/// state says "Queued for assistant" — queued is never dressed up as sent.
struct BrochureChooserSheet: View {
    @Environment(PricingService.self) private var pricing
    @Environment(BrochureService.self) private var brochures
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]

    @State private var selected: Set<String> = []  // "tripID:tier"
    @State private var email = ""
    @State private var errorMessage: String?
    @State private var doneRequests: [BrochureRequest]?
    @State private var didInit = false

    private var plan: PlanPricing {
        pricing.plan(trips: trips, settings: settingsRows.first, profile: profiles.first)
    }

    private struct RowItem: Identifiable {
        var trip: Trip
        var variant: VariantPricing
        var key: String { "\(trip.id.uuidString):\(variant.tier.rawValue)" }
        var id: String { key }
    }

    private var rows: [RowItem] {
        trips.flatMap { trip in
            (plan.trips[trip.id]?.variants ?? []).map { RowItem(trip: trip, variant: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let doneRequests {
                    doneState(doneRequests)
                } else {
                    chooser
                }
            }
            .navigationTitle("Get brochure email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(doneRequests == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !didInit else { return }
            didInit = true
            email = profiles.first?.email ?? ""
            // Primaries pre-ticked.
            selected = Set(rows.filter { $0.variant.isPrimary && $0.variant.total != nil }.map(\.key))
        }
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("One brochure per ticked stay — a PDF plus the plan as email text, queued for the assistant to send.")
                        .font(.subheadline).foregroundStyle(TP.dim)
                    ForEach(rows) { row in
                        rowView(row)
                    }
                    if rows.isEmpty {
                        Text("No priced trips yet — price a trip first, then queue its brochure.")
                            .font(.subheadline).foregroundStyle(TP.faint)
                    }
                    TextField("Email for the brochures", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 48)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(TP.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TP.white, lineWidth: 1))
                    }
                }
                .padding(16)
            }
            VStack(spacing: 8) {
                Text("\(selected.count) selected")
                    .font(.caption).foregroundStyle(TP.faint)
                Button("Send \(selected.count) brochure\(selected.count == 1 ? "" : "s")") {
                    Task { await send() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .background(TP.black)
        }
        .tpBackground()
    }

    private func rowView(_ row: RowItem) -> some View {
        let priced = row.variant.total != nil
        let destName = row.trip.destinationID.flatMap { pricing.catalog.destination(id: $0)?.name } ?? row.trip.customDestinationName ?? ""
        let title = row.trip.title.isEmpty ? destName : row.trip.title
        return Button {
            guard priced else { return }
            if selected.contains(row.key) { selected.remove(row.key) } else { selected.insert(row.key) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected.contains(row.key) ? "checkmark.square.fill" : "square")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(title) — \(row.variant.hotelName)")
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        if row.variant.isPrimary { Badge(label: "Primary", filled: true) }
                    }
                    Text("\(PricingEngine.dateString(row.trip.startDate)) – \(PricingEngine.dateString(row.trip.endDate))")
                        .font(.caption).foregroundStyle(TP.faint)
                    if !priced {
                        Text("Not priced: this stay isn't in the dataset")
                            .font(.caption).foregroundStyle(TP.faint)
                    }
                }
                Spacer()
                Text(TP.money(row.variant.total))
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!priced)
        .opacity(priced ? 1 : 0.45)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TP.separator, lineWidth: 1))
        .accessibilityLabel("\(title), \(row.variant.hotelName)\(priced ? "" : ", not priced")")
    }

    private func send() async {
        errorMessage = nil
        guard !selected.isEmpty else {
            errorMessage = "Tick at least one trip to send a brochure."
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), trimmed.contains("."), !trimmed.contains(" ") else {
            errorMessage = "That email doesn't look complete yet — check it and try again."
            return
        }
        let chosen = rows.filter { selected.contains($0.key) }
        let selections: [(trip: Trip, pricing: TripPricing, variant: VariantPricing)] = chosen.compactMap { row in
            guard let tp = plan.trips[row.trip.id] else { return nil }
            return (trip: row.trip, pricing: tp, variant: row.variant)
        }
        guard !selections.isEmpty else {
            errorMessage = "Couldn't queue that: nothing selected could be priced — nothing was sent."
            return
        }
        let created = await brochures.queue(
            selections: selections, recipient: trimmed,
            travellers: settingsRows.first?.travellers ?? 1, context: context)
        if created.allSatisfy({ $0.status == .failed }) {
            errorMessage = "Couldn't queue that: \(created.first?.summary ?? "unknown error") — nothing was sent."
        } else {
            doneRequests = created
        }
    }

    private func doneState(_ requests: [BrochureRequest]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Queued for assistant").font(.title3.bold())
                        Text("To \(requests.first?.recipient ?? "") · \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))")
                            .font(.caption).foregroundStyle(TP.faint)
                    }
                }
                ForEach(requests, id: \.id) { request in
                    HStack {
                        Text(request.summary).font(.subheadline)
                        Spacer()
                        Badge(label: request.status.label, filled: request.status == .sent)
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(TP.separator, lineWidth: 1))
                }
                Text("Queued is not sent — the assistant sends queued brochures from partheysmusebot@gmail.com.")
                    .font(.caption).foregroundStyle(TP.faint)
            }
            .padding(16)
        }
        .tpBackground()
    }
}
