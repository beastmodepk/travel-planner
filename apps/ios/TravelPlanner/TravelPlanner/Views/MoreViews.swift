import SwiftUI
import SwiftData

/// More tab: Profile, Planner settings, About & data sources. There is
/// deliberately NO Appearance section — jet black only, by design. (No
/// Brochures entry: queued brochures are held for the assistant, not
/// browsable in-app. No Passes & tickets entry: pass pricing is
/// engine-only, no panel.)
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label("Profile", systemImage: "person")
                            .frame(minHeight: 44)
                    }
                    NavigationLink {
                        PlannerSettingsView()
                    } label: {
                        Label("Planner settings", systemImage: "slider.horizontal.3")
                            .frame(minHeight: 44)
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About & data sources", systemImage: "info.circle")
                            .frame(minHeight: 44)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .tpBackground()
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The onboarding questions re-asked as a form, plus brochure email and an
/// explicit, confirmed "Apply profile defaults to my trips".
struct ProfileView: View {
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]
    @Environment(PricingService.self) private var pricing
    @Environment(\.modelContext) private var context
    @State private var confirmApply = false

    var body: some View {
        Group {
            if let profile = profiles.first {
                form(profile)
            } else {
                Text("No profile yet.").foregroundStyle(TP.dim)
            }
        }
        .tpBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func form(_ profile: Profile) -> some View {
        @Bindable var profile = profile
        return Form {
            Section("About you") {
                TextField("Name", text: $profile.name)
                TextField("Brochure email", text: $profile.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Home airport", text: $profile.homeAirport)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section("Ski") {
                Picker("Level", selection: $profile.level) {
                    ForEach(SkiLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                Picker("Pass held", selection: $profile.passHeld) {
                    ForEach(HeldPass.allCases) { pass in
                        Text(pass.label).tag(pass)
                    }
                }
                Picker("Gear", selection: $profile.gearOwned) {
                    ForEach(GearOwned.allCases) { gear in
                        Text(gear.label).tag(gear)
                    }
                }
            }
            Section("Travel") {
                Picker("Style", selection: $profile.travelStyle) {
                    ForEach(TravelStylePref.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("Vibe", selection: $profile.vibe) {
                    ForEach(Vibe.allCases) { vibe in
                        Text(vibe.label).tag(vibe)
                    }
                }
                Picker("Group", selection: $profile.group) {
                    ForEach(GroupSize.allCases) { group in
                        Text(group.label).tag(group)
                    }
                }
                Toggle("Work remotely on trips", isOn: $profile.remoteWork)
            }
            Section("Terrain you love") {
                FlowChips(
                    options: Terrain.allCases.map { (value: $0, label: $0.label) },
                    selected: Set(profile.terrain)
                ) { profile.terrain = Array($0) }
                .padding(.vertical, 4)
            }
            Section {
                Button("Apply profile defaults to my trips") { confirmApply = true }
                    .foregroundStyle(TP.white)
            } footer: {
                Text("Re-derives origin, traveller count and each trip's style/fare/gear from this profile. Destinations, dates and hotels are untouched.")
                    .foregroundStyle(TP.faint)
            }
        }
        .scrollContentBackground(.hidden)
        .onChange(of: profile.name) { _, _ in save(profile) }
        .onChange(of: profile.email) { _, _ in save(profile) }
        .onChange(of: profile.homeAirport) { _, _ in save(profile) }
        .confirmationDialog(
            "Apply profile defaults to all \(trips.count) trips?",
            isPresented: $confirmApply, titleVisibility: .visible
        ) {
            Button("Apply defaults") { applyDefaults(profile) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save(_ profile: Profile) {
        profile.updatedAt = Date()
        try? context.save()
    }

    private func applyDefaults(_ profile: Profile) {
        if let settings = settingsRows.first {
            settings.origin = profile.homeAirport.uppercased()
            settings.travellers = profile.group.travellers
            settings.updatedAt = Date()
        }
        let gear = Seeding.profileGear(profile)
        let style = Seeding.profileStyle(profile)
        for trip in trips {
            let dest = trip.destinationID.flatMap { pricing.catalog.destination(id: $0) }
            let draft = Seeding.TripDraft(
                destinationID: trip.destinationID, customName: trip.customDestinationName,
                tripTypeID: trip.tripTypeID, window: trip.windowSelection,
                start: PricingEngine.dateString(trip.startDate), end: PricingEngine.dateString(trip.endDate),
                skiDays: trip.activityDays, style: trip.style, fareClass: trip.fareClass,
                primaryTier: trip.primaryVariant?.tier ?? .comfort,
                selectedTiers: trip.selectedVariants.map(\.tier), gear: trip.gear)
            let next = Seeding.applyStyle(draft, style: style, socialTier: dest?.socialTier ?? .comfort, gearDefault: gear)
            trip.style = next.style
            trip.fareClass = next.fareClass
            trip.gear = next.gear
            for variant in trip.hotelVariants {
                variant.isSelected = next.selectedTiers.contains(variant.tier)
                variant.isPrimary = variant.tier == next.primaryTier
            }
            trip.touch()
        }
        try? context.save()
    }
}

/// Origin, travellers, custom destinations (≤20).
struct PlannerSettingsView: View {
    @Query private var settingsRows: [PlannerSettings]
    @Query(sort: \CustomDestination.createdAt) private var customs: [CustomDestination]
    @Environment(\.modelContext) private var context
    @State private var newCustom = ""

    var body: some View {
        Group {
            if let settings = settingsRows.first {
                @Bindable var settings = settings
                Form {
                    Section("Planner") {
                        TextField("Origin airport", text: $settings.origin)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Stepper(value: $settings.travellers, in: 1...8) {
                            Text("Travellers: \(settings.travellers)")
                        }
                        Text("Flights are priced from the origin. The dataset covers BOS departures today — other origins price everything except the flight, and say so.")
                            .font(.caption).foregroundStyle(TP.faint)
                    }
                    Section("Custom places (\(customs.count)/20)") {
                        ForEach(customs, id: \.id) { custom in
                            Text(custom.name)
                        }
                        .onDelete { offsets in
                            offsets.forEach { context.delete(customs[$0]) }
                            try? context.save()
                        }
                        HStack {
                            TextField("Add a place", text: $newCustom)
                            Button("Add") {
                                let name = newCustom.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty, customs.count < 20 else { return }
                                let custom = CustomDestination()
                                custom.id = "custom-\(UUID().uuidString.prefix(8))"
                                custom.name = name
                                context.insert(custom)
                                try? context.save()
                                newCustom = ""
                            }
                            .disabled(newCustom.trimmingCharacters(in: .whitespaces).isEmpty || customs.count >= 20)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: settings.origin) { _, _ in try? context.save() }
                .onChange(of: settings.travellers) { _, _ in try? context.save() }
            }
        }
        .tpBackground()
        .navigationTitle("Planner settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Provenance in plain words — the trust layer of the whole app.
struct AboutView: View {
    @Environment(PricingService.self) private var pricing

    var body: some View {
        let catalog = pricing.catalog
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("About & data sources").font(.title2.bold())
                Text("Travel Planner prices trips from a researched dataset — not live inventory. Prices were checked \(catalog.checkedAt) (dataset v\(catalog.datasetVersion)): flights via Duffel, hotels via Expedia, lift tickets and passes from the official resort shops and Epic.")
                    .font(.body).foregroundStyle(TP.dim)
                Text("Two trip types: Ski — West Coast (Park City, Tahoe–Heavenly, Alta/Snowbird, Jackson Hole, Breckenridge) and Ski — Japan (Niseko).")
                    .font(.body).foregroundStyle(TP.dim)
                Text("Figures marked ~ are estimates (extended day counts, prorated hotel nights, converted currencies). Flights are priced from \(catalog.origin); other origins price everything except the flight, and say so.")
                    .font(.body).foregroundStyle(TP.dim)
                Text("Nothing is booked in this app — booking links go to the sellers (Google Flights, Expedia, the resorts). Check the seller's live price before you buy; the dataset's checked date is shown on every trip.")
                    .font(.body).foregroundStyle(TP.dim)
                Text("AI research provider: not configured in this build. When it arrives it will run through our own backend — this app never holds an API key.")
                    .font(.body).foregroundStyle(TP.dim)
                Text("Privacy: everything lives on this device. No accounts, no analytics, no tracking — Data Not Collected.")
                    .font(.body).foregroundStyle(TP.dim)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tpBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
