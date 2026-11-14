import SwiftUI
import SwiftData

/// Trips tab: phase tabs with counts, display-only filter + sort, collapsed
/// cards, Past trips in a collapsed bottom section, brochure chooser in the
/// header. (The Epic Pass pricing is engine-only — no panel UI.)
struct TripsView: View {
    @Environment(PricingService.self) private var pricing
    @Environment(ViewPrefs.self) private var prefs
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]
    @State private var showBrochureChooser = false
    @State private var showAddTrip = false
    @State private var pastExpanded = false

    private var catalog: Catalog { pricing.catalog }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        filterRow
                        phaseChips
                        tripSections
                        addTripButton
                    }
                    .padding(16)
                }
                .onChange(of: navigation.highlightedTripID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if navigation.highlightedTripID == id { navigation.highlightedTripID = nil }
                    }
                }
            }
            .tpBackground()
            .navigationTitle("Your trips")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: editorBinding) { trip in
                TripEditorView(trip: trip)
            }
            .sheet(isPresented: $showBrochureChooser) {
                BrochureChooserSheet()
            }
            .sheet(isPresented: $showAddTrip) {
                AddTripSheet()
            }
            .onAppear {
                if let id = navigation.editorTripID, trips.contains(where: { $0.id == id }) {
                    navigation.editorTripID = nil
                    editorTrip = trips.first { $0.id == id }
                }
            }
            .onChange(of: navigation.editorTripID) { _, id in
                guard let id, let trip = trips.first(where: { $0.id == id }) else { return }
                navigation.editorTripID = nil
                editorTrip = trip
            }
        }
    }

    @State private var editorTrip: Trip?
    private var editorBinding: Binding<Trip?> {
        Binding(get: { editorTrip }, set: { editorTrip = $0 })
    }

    private var plan: PlanPricing {
        pricing.plan(trips: trips, settings: settingsRows.first, profile: profiles.first)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Your trips").font(.largeTitle.bold())
            Spacer()
            Button {
                showBrochureChooser = true
            } label: {
                Label("Brochure", systemImage: "envelope")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TP.white, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get brochure email")
        }
    }

    private var filterRow: some View {
        @Bindable var prefs = prefs
        return HStack(spacing: 10) {
            TextField("Filter by name or place…", text: $prefs.tripFilter)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            Menu {
                Picker("Sort", selection: $prefs.tripSort) {
                    ForEach(TripSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(prefs.tripSort.label).font(.subheadline.bold())
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Sort trips")
        }
    }

    private var phaseChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhaseTab.allCases) { tab in
                    let count = tab.phase.map { phase in trips.filter { $0.phase == phase }.count } ?? trips.count
                    Chip(label: "\(tab.label) (\(count))", selected: prefs.phaseTab == tab) {
                        prefs.phaseTab = tab
                    }
                }
            }
        }
    }

    private func visibleTrips(excludingPast: Bool) -> [Trip] {
        var list = trips
        if let phase = prefs.phaseTab.phase {
            list = list.filter { $0.phase == phase }
        } else if excludingPast {
            list = list.filter { $0.phase != .past }
        } else {
            list = list.filter { $0.phase == .past }
        }
        let q = prefs.tripFilter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { trip in
                let name = trip.destinationID.flatMap { catalog.destination(id: $0)?.name } ?? trip.customDestinationName ?? ""
                return name.lowercased().contains(q) || trip.title.lowercased().contains(q)
            }
        }
        switch prefs.tripSort {
        case .manual: list.sort { $0.sortIndex < $1.sortIndex }
        case .name: list.sort { displayName($0) < displayName($1) }
        case .priceAsc: list.sort { (plan.trips[$0.id]?.total ?? .infinity) < (plan.trips[$1.id]?.total ?? .infinity) }
        case .priceDesc: list.sort { (plan.trips[$0.id]?.total ?? 0) > (plan.trips[$1.id]?.total ?? 0) }
        case .date: list.sort { $0.startDate < $1.startDate }
        }
        return list
    }

    private func displayName(_ trip: Trip) -> String {
        trip.title.isEmpty
            ? (trip.destinationID.flatMap { catalog.destination(id: $0)?.name } ?? trip.customDestinationName ?? "")
            : trip.title
    }

    @ViewBuilder
    private var tripSections: some View {
        let main = visibleTrips(excludingPast: true)
        if main.isEmpty && prefs.phaseTab.phase != .past {
            Text("No trips here yet — plan one from Explore.")
                .font(.subheadline)
                .foregroundStyle(TP.faint)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        }
        ForEach(main) { trip in
            TripCardView(
                trip: trip,
                pricing: plan.trips[trip.id],
                catalog: catalog,
                highlighted: navigation.highlightedTripID == trip.id
            ) { editorTrip = trip }
            .id(trip.id)
        }

        if prefs.phaseTab == .all {
            let past = visibleTrips(excludingPast: false)
            DisclosureGroup(isExpanded: $pastExpanded) {
                VStack(spacing: 18) {
                    ForEach(past) { trip in
                        TripCardView(
                            trip: trip,
                            pricing: plan.trips[trip.id],
                            catalog: catalog
                        ) { editorTrip = trip }
                        .id(trip.id)
                    }
                    if past.isEmpty {
                        Text("No past trips yet.").font(.subheadline).foregroundStyle(TP.faint)
                    }
                }
                .padding(.top, 12)
            } label: {
                Text("Past trips (\(past.count))")
                    .font(.headline)
                    .foregroundStyle(TP.white)
                    .frame(minHeight: 44)
            }
            .tint(TP.white)
        } else if prefs.phaseTab == .past {
            let past = visibleTrips(excludingPast: false)
            ForEach(past) { trip in
                TripCardView(
                    trip: trip,
                    pricing: plan.trips[trip.id],
                    catalog: catalog
                ) { editorTrip = trip }
                .id(trip.id)
            }
        }
    }

    private var addTripButton: some View {
        Button {
            showAddTrip = true
        } label: {
            Label("Add a trip", systemImage: "plus")
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

/// Add-a-trip sheet: pick a catalog destination or save a custom place
/// (custom trips are honestly unpriced until researched).
struct AddTripSheet: View {
    @Environment(PricingService.self) private var pricing
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]
    @Query private var customs: [CustomDestination]
    @State private var customName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Destinations") {
                    ForEach(pricing.catalog.destinations) { dest in
                        Button {
                            addTrip(destinationID: dest.id, customName: nil, tripTypeID: dest.tripTypeID)
                        } label: {
                            HStack {
                                Text("\(dest.name), \(dest.state)").foregroundStyle(TP.white)
                                Spacer()
                                Text(pricing.catalog.tripType(id: dest.tripTypeID).shortLabel)
                                    .font(.caption).foregroundStyle(TP.faint)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                Section("Custom place") {
                    TextField("Place name (e.g. Revelstoke)", text: $customName)
                        .frame(minHeight: 44)
                    Button("Add custom place") {
                        let name = customName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, customs.count < 20 else { return }
                        let custom = CustomDestination()
                        custom.id = "custom-\(UUID().uuidString.prefix(8))"
                        custom.name = name
                        context.insert(custom)
                        addTrip(destinationID: nil, customName: name, tripTypeID: "ski-west")
                    }
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty || customs.count >= 20)
                    if customs.count >= 20 {
                        Text("Custom places are capped at 20.").font(.caption).foregroundStyle(TP.faint)
                    }
                    Text("Custom places save with dates and style, but stay unpriced until they're researched into the dataset.")
                        .font(.caption).foregroundStyle(TP.faint)
                }
            }
            .scrollContentBackground(.hidden)
            .tpBackground()
            .navigationTitle("Add a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func addTrip(destinationID: String?, customName: String?, tripTypeID: String) {
        let profile = profiles.first
        let style = profile.map { Seeding.profileStyle($0) } ?? .balanced
        let gear = profile.map { Seeding.profileGear($0) } ?? .auto
        let dest = destinationID.flatMap { pricing.catalog.destination(id: $0) }
        let window: WindowSelection = dest?.region == "japan" ? .jan : .dec
        let windowDef = pricing.catalog.window(id: window.rawValue)
        let draft = Seeding.applyStyle(
            Seeding.TripDraft(
                destinationID: destinationID, customName: customName, tripTypeID: tripTypeID,
                window: window, start: windowDef?.start ?? "2026-12-19", end: windowDef?.end ?? "2026-12-23",
                skiDays: 3, style: style, fareClass: .basic, primaryTier: .comfort,
                selectedTiers: [.comfort], gear: gear),
            style: style, socialTier: dest?.socialTier ?? .comfort, gearDefault: gear)
        let trip = Seeding.makeTrip(
            from: draft, catalog: pricing.catalog,
            sortIndex: (trips.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(trip)
        try? context.save()
        dismiss()
    }
}
