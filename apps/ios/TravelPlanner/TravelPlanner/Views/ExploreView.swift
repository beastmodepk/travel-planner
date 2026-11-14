import SwiftUI
import SwiftData

/// Destinations gallery. Default filter is All types — Niseko is never
/// hidden on first open (a lesson learned on the web).
struct ExploreView: View {
    @Environment(PricingService.self) private var pricing
    @Environment(ViewPrefs.self) private var prefs
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]

    private var catalog: Catalog { pricing.catalog }

    var body: some View {
        @Bindable var prefs = prefs
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    TextField("Filter by name or place…", text: $prefs.galleryFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 44)
                    typeChips
                    Text("Prices from: January · from \(settingsRows.first?.origin ?? "BOS") · 1 traveller · 3 ski days · cheapest stay & gear — a starting point, not a firm quote.")
                        .font(.subheadline)
                        .foregroundStyle(TP.dim)
                    sortRow
                    gallery
                }
                .padding(16)
            }
            .tpBackground()
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hello\(profiles.first.map { $0.name.isEmpty ? "" : ", \($0.name)" } ?? "")")
                .font(.largeTitle.bold())
            Text("Flying from \(settingsRows.first?.origin ?? "BOS") · \(settingsRows.first?.travellers ?? 1) traveller\((settingsRows.first?.travellers ?? 1) == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(TP.dim)
        }
    }

    private var typeChips: some View {
        @Bindable var prefs = prefs
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(label: "All types", selected: prefs.galleryType == "all") { prefs.galleryType = "all" }
                ForEach(catalog.tripTypes) { type in
                    Chip(label: type.shortLabel,
                         selected: prefs.galleryType == type.id) {
                        prefs.galleryType = type.id
                    }
                }
            }
        }
    }

    private var sortRow: some View {
        @Bindable var prefs = prefs
        return HStack {
            Text("Sort").font(.subheadline).foregroundStyle(TP.faint)
            Menu {
                Picker("Sort", selection: $prefs.gallerySort) {
                    ForEach(GallerySort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(prefs.gallerySort.label).font(.subheadline.bold())
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .foregroundStyle(TP.white)
                .frame(minHeight: 44)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var gallery: some View {
        let destinations = filteredDestinations()
        if destinations.isEmpty {
            VStack(spacing: 12) {
                Text("Nothing matches \"\(prefs.galleryFilter)\"")
                    .font(.headline)
                Button("Clear filter") { prefs.galleryFilter = "" }
                    .buttonStyle(TertiaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            ForEach(destinations) { dest in
                destinationCard(dest)
            }
        }
    }

    private func filteredDestinations() -> [Destination] {
        var list = catalog.destinations
        // A persisted filter may name a removed trip type — ignore it
        // (treat as "all") rather than showing an empty gallery.
        if prefs.galleryType != "all", catalog.tripTypes.contains(where: { $0.id == prefs.galleryType }) {
            list = list.filter { $0.tripTypeID == prefs.galleryType }
        }
        let q = prefs.galleryFilter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) || $0.state.lowercased().contains(q) || $0.shortName.lowercased().contains(q)
            }
        }
        switch prefs.gallerySort {
        case .curated: break
        case .name: list.sort { $0.name < $1.name }
        case .priceAsc: list.sort { (priceFrom($0) ?? .infinity) < (priceFrom($1) ?? .infinity) }
        case .priceDesc: list.sort { (priceFrom($0) ?? 0) > (priceFrom($1) ?? 0) }
        case .snow: list.sort { $0.snowScore > $1.snowScore }
        case .social: list.sort { $0.socialScore > $1.socialScore }
        }
        return list
    }

    private func priceFrom(_ dest: Destination) -> Double? {
        // Cheapest window drives the "from" figure; January unless December wins.
        let dec = pricing.priceFrom(destinationID: dest.id, window: "dec")
        let jan = pricing.priceFrom(destinationID: dest.id, window: "jan")
        return [dec, jan].compactMap { $0 }.min()
    }

    private func priceFromWindow(_ dest: Destination) -> String {
        let dec = pricing.priceFrom(destinationID: dest.id, window: "dec")
        let jan = pricing.priceFrom(destinationID: dest.id, window: "jan")
        if let jan, dec == nil || jan <= dec! { return "Jan" }
        return "Dec"
    }

    private func destinationCard(_ dest: Destination) -> some View {
        let planned = trips.first { $0.destinationID == dest.id }
        return VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DestinationPhoto(destination: dest, height: 220)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Badge(label: catalog.tripType(id: dest.tripTypeID).shortLabel, onPhoto: true)
                        Badge(label: "Social \(dest.socialScore) · Snow \(dest.snowScore)", onPhoto: true)
                    }
                    Text("\(dest.name), \(dest.state)")
                        .font(.title2.bold())
                        .accessibilityLabel("\(dest.name). Social \(dest.socialScore) of 10. Snow \(dest.snowScore) of 10.")
                    Text(dest.blurb)
                        .font(.subheadline)
                        .foregroundStyle(TP.dim)
                        .lineLimit(2)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(priceFromWindow(dest)) from")
                                .font(.caption).foregroundStyle(TP.faint)
                            Text(TP.moneyApprox(priceFrom(dest)))
                                .font(.title.bold())
                                .monospacedDigit()
                                .accessibilityLabel("From approximately \(TP.money(priceFrom(dest)))")
                        }
                        Spacer()
                        if let planned {
                            Button("View trip ↓") { navigation.viewTrip(planned.id) }
                                .buttonStyle(SecondaryButtonStyle())
                                .frame(width: 150)
                        } else {
                            Button("Plan this trip") { planTrip(dest) }
                                .buttonStyle(PrimaryButtonStyle())
                                .frame(width: 170)
                        }
                    }
                }
                .padding(14)
                .glassPanel()
                .padding(12)
            }
        }
        .background(TP.black)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func planTrip(_ dest: Destination) {
        let profile = profiles.first
        let style = profile.map { Seeding.profileStyle($0) } ?? .balanced
        let gear = profile.map { Seeding.profileGear($0) } ?? .auto
        let window: WindowSelection = dest.region == "japan" ? .jan : .dec
        let windowDef = catalog.window(id: window.rawValue)
        let draft = Seeding.applyStyle(
            Seeding.TripDraft(
                destinationID: dest.id, customName: nil, tripTypeID: dest.tripTypeID,
                window: window, start: windowDef?.start ?? "2026-12-19", end: windowDef?.end ?? "2026-12-23",
                skiDays: 3, style: style, fareClass: .basic, primaryTier: .comfort,
                selectedTiers: [.comfort], gear: gear),
            style: style, socialTier: dest.socialTier, gearDefault: gear)
        let trip = Seeding.makeTrip(from: draft, catalog: catalog, sortIndex: (trips.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(trip)
        try? context.save()
        navigation.editTrip(trip.id)
    }
}
