import SwiftUI
import SwiftData

/// The trip editor: one scroll, grouped sections, sticky bottom total.
/// Text fields are NEVER disabled during repricing (pricing is on-device
/// and instant, so the web's lock state doesn't exist here by construction).
struct TripEditorView: View {
    @Bindable var trip: Trip
    @Environment(PricingService.self) private var pricing
    @Environment(ViewPrefs.self) private var prefs
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.sortIndex) private var allTrips: [Trip]
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]
    @Query private var picks: [ComparePick]
    @State private var hotelTagFilter = "All"
    @State private var flightFareFilter = "all"
    @State private var showTypeSheet = false
    @State private var showDestinationSheet = false
    @State private var openBox: EditorBox?
    @State private var boxDone: [String: String] = [:]
    @State private var boxesInitialised = false

    /// The editor's picking boxes, in flow order. Transfers are a single
    /// researched line, not a choice, so they get no box.
    private enum EditorBox: String, CaseIterable {
        case basics, flights, hotels, lift, gear
        var title: String {
            switch self {
            case .basics: return "Basics"
            case .flights: return "Flights"
            case .hotels: return "Accommodation"
            case .lift: return "Lift / Pass"
            case .gear: return "Gear"
            }
        }
    }

    private var catalog: Catalog { pricing.catalog }
    private var plan: PlanPricing {
        pricing.plan(trips: allTrips, settings: settingsRows.first, profile: profiles.first)
    }
    private var tripPricing: TripPricing? { plan.trips[trip.id] }
    private var destination: Destination? { trip.destinationID.flatMap { catalog.destination(id: $0) } }
    private var destName: String {
        destination?.name ?? trip.customDestinationName ?? "Trip"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DestinationPhoto(destination: destination, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                phaseSection
                editorBox(.basics, summary: basicsSummary) { basicsBoxContent }
                editorBox(.flights, summary: flightsSummary) { flightsBoxContent }
                editorBox(.hotels, summary: hotelsSummary) { hotelsBoxContent }
                editorBox(.lift, summary: liftSummary) { liftBoxContent }
                editorBox(.gear, summary: gearSummary) { gearBoxContent }
                notesSection
                breakdownSection
                Spacer(minLength: 90)
            }
            .padding(16)
        }
        .tpBackground()
        .navigationTitle(trip.title.isEmpty ? destName : trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip total").font(.caption).foregroundStyle(TP.faint)
                    Text(TP.money(tripPricing?.total))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.headline)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 48)
                    .background(TP.white)
                    .foregroundStyle(TP.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(TP.black)
            .overlay(Rectangle().fill(TP.hairline).frame(height: 1), alignment: .top)
        }
        .sheet(isPresented: $showTypeSheet) { typeSheet }
        .sheet(isPresented: $showDestinationSheet) { destinationSheet }
        .onAppear { initialiseBoxes() }
    }

    private func save() {
        trip.touch()
        Seeding.refreshVariantTags(for: trip, catalog: catalog)
        try? context.save()
    }

    // MARK: Editor boxes (accordion flow)
    //
    // A box is DECIDED only by an explicit user action in this flow: a pick
    // (flight row, Make primary, gear row), Done (confirm — including
    // confirming a default), or Skip. Priced defaults are NOT decisions:
    // the anchor flight (flightOptionID empty) and gear "auto" leave their
    // boxes undecided, so they load open. Decisions persist per trip in
    // ViewPrefs (keyed by trip id); on load a box opens unless decided.

    private func initialiseBoxes() {
        guard !boxesInitialised else { return }
        boxesInitialised = true
        for box in EditorBox.allCases {
            if let status = prefs.boxStatus(tripID: trip.id, box: box.rawValue) {
                boxDone[box.rawValue] = status
            }
        }
        openBox = EditorBox.allCases.first { boxDone[$0.rawValue] == nil }
    }

    private func toggleBox(_ box: EditorBox) {
        openBox = openBox == box ? nil : box
    }

    /// Record a box as decided ("picked" = picked or confirmed, or
    /// "skipped"), collapse it, and open the next undecided box.
    /// Display state only — never affects pricing.
    private func markBox(_ box: EditorBox, status: String) {
        boxDone[box.rawValue] = status
        prefs.setBoxStatus(tripID: trip.id, box: box.rawValue, status: status)
        openBox = EditorBox.allCases.first { boxDone[$0.rawValue] == nil }
    }

    /// Changing the inputs a box depends on reopens it (decision cleared).
    private func clearBoxes(_ boxes: [EditorBox]) {
        for box in boxes {
            boxDone[box.rawValue] = nil
            prefs.setBoxStatus(tripID: trip.id, box: box.rawValue, status: nil)
        }
    }

    private func editorBox<Content: View>(_ box: EditorBox, summary: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { toggleBox(box) } label: {
                HStack(spacing: 10) {
                    Text(box.title).font(.headline).foregroundStyle(TP.white)
                    Text(summary)
                        .font(.caption).foregroundStyle(TP.faint)
                        .lineLimit(1)
                    Spacer()
                    if boxDone[box.rawValue] == "picked" {
                        Badge(label: "✓ Done", filled: true)
                    } else if boxDone[box.rawValue] == "skipped" {
                        Badge(label: "Skipped", filled: false)
                    }
                    Image(systemName: openBox == box ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(TP.faint)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(box.title). \(summary)")
            if openBox == box {
                content()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.separator, lineWidth: 1))
    }

    private func boxButtons(_ box: EditorBox, skippable: Bool) -> some View {
        HStack(spacing: 18) {
            Button("Done") { markBox(box, status: "picked") }
                .font(.subheadline.bold())
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TP.white, lineWidth: 1.5))
                .buttonStyle(.plain)
            if skippable {
                Button("Skip") { markBox(box, status: "skipped") }
                    .font(.subheadline).underline()
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: Box summaries (one line each, shown when collapsed)

    private var basicsSummary: String {
        "\(destName) · \(PricingEngine.dateString(trip.startDate)) – \(PricingEngine.dateString(trip.endDate)) · \(trip.activityDays) ski day\(trip.activityDays == 1 ? "" : "s")"
    }

    private var flightsSummary: String {
        tripPricing?.flightSummary ?? "Not priced yet"
    }

    private var hotelsSummary: String {
        guard let result = tripPricing?.result, let primary = trip.primaryVariant,
              let option = result.hotelOptions.first(where: { $0.key == primary.tier.rawValue })
        else { return "Not priced yet" }
        let extra = trip.selectedVariants.count > 1 ? " +\(trip.selectedVariants.count - 1) more" : ""
        return "\(option.label)\(extra) · \(TP.money(option.amount))"
    }

    private var liftSummary: String {
        guard let line = tripPricing?.lines.first(where: { $0.key == "lift" }) else { return "Not priced yet" }
        return "\(line.label) · \(TP.money(line.amount))\(line.estimate ? " ~" : "")"
    }

    private var gearSummary: String {
        guard let result = tripPricing?.result, let key = result.chosenGearKey,
              let gear = result.gearOptions.first(where: { $0.key == key })
        else { return "Not priced yet" }
        return "\(gear.label) · \(TP.money(gear.amount))"
    }

    // MARK: Phase

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Phase")
            Picker("Phase", selection: phaseBinding) {
                ForEach(TripPhase.allCases) { phase in
                    Text(phase.shortLabel).tag(phase)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Trip phase")
        }
    }

    private var phaseBinding: Binding<TripPhase> {
        Binding(get: { trip.phase }, set: { trip.phase = $0; save() })
    }

    // MARK: Basics box (fields + ski days + style preset)

    private var basicsBoxContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Trip name (optional)", text: $trip.title)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 48)
                .onChange(of: trip.title) { _, _ in save() }
            editorRow(label: "Trip type", value: catalog.tripType(id: trip.tripTypeID).label) {
                showTypeSheet = true
            }
            editorRow(label: "Destination", value: destName) {
                showDestinationSheet = true
            }
            HStack(spacing: 8) {
                ForEach([WindowSelection.dec, .jan, .custom], id: \.self) { w in
                    Chip(label: w == .dec ? "December" : w == .jan ? "January" : "Custom dates",
                         selected: trip.windowSelection == w) {
                        applyWindow(w)
                    }
                }
            }
            .padding(.vertical, 4)
            DatePicker("From", selection: startBinding, displayedComponents: .date)
                .frame(minHeight: 48)
            DatePicker("To", selection: endBinding, displayedComponents: .date)
                .frame(minHeight: 48)
            Stepper(value: daysBinding, in: 1...10) {
                HStack {
                    Text("Ski days").foregroundStyle(TP.dim)
                    Spacer()
                    Text("\(trip.activityDays) day\(trip.activityDays == 1 ? "" : "s")").bold()
                }
            }
            .frame(minHeight: 48)
            Text((3...4).contains(trip.activityDays)
                 ? "Researched range — figures from the Nov 13, 2026 dataset."
                 : "Extended estimate — outside the researched 3–4 day range, extended per day and marked ~.")
                .font(.caption).foregroundStyle(TP.faint)
            Text("Style preset — sets fare class, hotel pick and gear at once; those boxes reopen below so you can review each pick.")
                .font(.caption).foregroundStyle(TP.faint)
                .padding(.top, 6)
            FlowLayout(spacing: 8) {
                ForEach(catalog.styles) { style in
                    Chip(label: style.label, selected: trip.styleRaw == style.id) {
                        applyStyle(TripStyle(rawValue: style.id) ?? .balanced)
                    }
                }
            }
            if let style = catalog.style(id: trip.styleRaw) {
                Text(style.blurb).font(.caption).foregroundStyle(TP.dim)
            }
            boxButtons(.basics, skippable: false)
        }
    }

    private var daysBinding: Binding<Int> {
        Binding(get: { trip.activityDays }, set: { trip.activityDays = $0; clearBoxes([.lift, .gear]); save() })
    }

    private var startBinding: Binding<Date> {
        Binding(get: { trip.startDate }, set: { trip.startDate = $0; trip.windowSelection = .custom; clearBoxes([.flights, .hotels, .lift, .gear]); save() })
    }
    private var endBinding: Binding<Date> {
        Binding(get: { trip.endDate }, set: { trip.endDate = $0; trip.windowSelection = .custom; clearBoxes([.flights, .hotels, .lift, .gear]); save() })
    }

    private func applyWindow(_ w: WindowSelection) {
        trip.windowSelection = w
        if let def = catalog.window(id: w.rawValue),
           let start = PricingEngine.date(fromString: def.start),
           let end = PricingEngine.date(fromString: def.end) {
            trip.startDate = start
            trip.endDate = end
        }
        clearBoxes([.flights, .hotels, .lift, .gear])
        save()
    }

    private func editorRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(TP.dim)
                Spacer()
                Text(value).bold().foregroundStyle(TP.white)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(TP.faint)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Flights box
    //
    // Fare class lives here now (there is no separate fare picker): the
    // filter chips narrow the list and picking a flight syncs the class.

    private var flightsBoxContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result = tripPricing?.result, !result.flightOptions.isEmpty {
                Text("Researched snapshot, checked \(result.checkedAt) — times are representative for the route; live times vary by date. Pick one flight: it sets the Flight line and the trip total.")
                    .font(.caption).foregroundStyle(TP.faint)
                HStack(spacing: 8) {
                    ForEach([("all", "All"), ("basic", "Basic"), ("flex", "Flex")], id: \.0) { pair in
                        Chip(label: pair.1, selected: flightFareFilter == pair.0) { flightFareFilter = pair.0 }
                    }
                }
                ForEach(result.flightOptions.filter { flightFareFilter == "all" || $0.fareClass.rawValue == flightFareFilter }) { option in
                    flightRow(option)
                }
                googleFlightsLink
            } else {
                Text("Flights aren't priced for departures from \((settingsRows.first?.origin ?? "BOS").uppercased()) in the researched dataset.")
                    .font(.subheadline).foregroundStyle(TP.faint)
                googleFlightsLink
            }
            boxButtons(.flights, skippable: true)
        }
    }

    @ViewBuilder
    private var googleFlightsLink: some View {
        if let dest = destination,
           let url = URL(string: PricingEngine.googleFlightsUrl(
               origin: (settingsRows.first?.origin ?? "BOS").uppercased(),
               dest: dest,
               start: PricingEngine.dateString(trip.startDate),
               end: PricingEngine.dateString(trip.endDate))) {
            Link("See live flights on Google Flights ↗", destination: url)
                .font(.subheadline).underline().frame(minHeight: 44)
        }
    }

    private func flightRow(_ option: FlightOptionInfo) -> some View {
        Button {
            trip.flightOptionID = option.id
            trip.fareClass = option.fareClass
            save()
            markBox(.flights, status: "picked")
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: option.selected ? "checkmark.circle.fill" : "circle")
                    .frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.airline).font(.headline)
                        ForEach(option.tags, id: \.self) { tag in
                            Badge(label: tag == "best" ? "Best" : "Cheapest", filled: true)
                        }
                    }
                    Text("Out \(legText(option.outbound, date: trip.startDate))")
                        .font(.caption)
                        .foregroundStyle(option.selected ? TP.black.opacity(0.65) : TP.faint)
                    Text("Back \(legText(option.inbound, date: trip.endDate))")
                        .font(.caption)
                        .foregroundStyle(option.selected ? TP.black.opacity(0.65) : TP.faint)
                    Text("\(option.fareClass.label) fare\(option.bagIncluded ? " · 1 checked bag included" : "")")
                        .font(.caption)
                        .foregroundStyle(option.selected ? TP.black.opacity(0.65) : TP.faint)
                }
                Spacer()
                Text(TP.money(option.amount))
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(12)
            .frame(minHeight: 56)
            .background(option.selected ? TP.white : Color.clear)
            .foregroundStyle(option.selected ? TP.black : TP.white)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(option.selected ? TP.white : TP.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.airline). \(option.detail). \(TP.money(option.amount))")
    }

    private func legText(_ leg: FlightLeg, date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return "\(f.string(from: date)) · \(leg.depart) → \(leg.arrive)\(leg.arriveNextDay > 0 ? " +\(leg.arriveNextDay)" : "") · \(leg.duration) · \(leg.stopsLabel)"
    }

    // MARK: Style (lives inside the Basics box)

    private func applyStyle(_ style: TripStyle) {
        let draft = Seeding.TripDraft(
            destinationID: trip.destinationID, customName: trip.customDestinationName,
            tripTypeID: trip.tripTypeID, window: trip.windowSelection,
            start: PricingEngine.dateString(trip.startDate), end: PricingEngine.dateString(trip.endDate),
            skiDays: trip.activityDays, style: trip.style, fareClass: trip.fareClass,
            primaryTier: trip.primaryVariant?.tier ?? .comfort,
            selectedTiers: trip.selectedVariants.map(\.tier), gear: trip.gear)
        let gearDefault = profiles.first.map { Seeding.profileGear($0) } ?? .auto
        let next = Seeding.applyStyle(draft, style: style, socialTier: destination?.socialTier ?? .comfort, gearDefault: gearDefault)
        trip.style = next.style
        trip.fareClass = next.fareClass
        trip.flightOptionID = ""  // preset fare class re-selects its anchor flight
        trip.gear = next.gear
        for variant in trip.hotelVariants {
            variant.isSelected = next.selectedTiers.contains(variant.tier)
            variant.isPrimary = variant.tier == next.primaryTier
        }
        // A preset changes fare, hotel and gear programmatically — those
        // are not user decisions, so their boxes reopen for review.
        clearBoxes([.flights, .hotels, .gear])
        save()
    }

    // MARK: Hotels

    private var hotelTagOptions: [String] {
        var tags = Set<String>()
        trip.hotelVariants.forEach { tags.formUnion($0.tags) }
        return ["All"] + tags.sorted()
    }

    private var hotelsBoxContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Primary drives the trip total. Price checked Nov 13, 2026 — Expedia's live price may have moved.")
                .font(.caption).foregroundStyle(TP.faint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hotelTagOptions, id: \.self) { tag in
                        Chip(label: tag, selected: hotelTagFilter == tag) { hotelTagFilter = tag }
                    }
                    Spacer()
                    Menu {
                        Picker("Hotel sort", selection: hotelSortBinding) {
                            Text("Price").tag(HotelSort.price)
                            Text("Name").tag(HotelSort.name)
                        }
                    } label: {
                        Text("Sort: \(prefs.hotelSort.label)")
                            .font(.subheadline.bold())
                            .frame(minHeight: 44)
                    }
                }
            }
            ForEach(sortedVariants(), id: \.id) { variant in
                hotelRow(variant)
            }
            boxButtons(.hotels, skippable: false)
        }
    }

    private var hotelSortBinding: Binding<HotelSort> {
        Binding(get: { prefs.hotelSort }, set: { prefs.hotelSort = $0 })
    }

    private func sortedVariants() -> [HotelVariant] {
        var list = trip.hotelVariants
        if hotelTagFilter != "All" {
            list = list.filter { $0.tags.contains(hotelTagFilter) }
        }
        let options = tripPricing?.result.hotelOptions ?? []
        switch prefs.hotelSort {
        case .price:
            list.sort { a, b in
                let av = options.first { $0.key == a.tier.rawValue }?.amount ?? .infinity
                let bv = options.first { $0.key == b.tier.rawValue }?.amount ?? .infinity
                return av < bv
            }
        case .name:
            list.sort { a, b in
                let an = options.first { $0.key == a.tier.rawValue }?.label ?? ""
                let bn = options.first { $0.key == b.tier.rawValue }?.label ?? ""
                return an < bn
            }
        }
        return list
    }

    private func hotelRow(_ variant: HotelVariant) -> some View {
        let option = tripPricing?.result.hotelOptions.first { $0.key == variant.tier.rawValue }
        let isLastSelected = variant.isSelected && trip.selectedVariants.count == 1
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleSelected(variant)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: variant.isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .frame(minHeight: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(option?.label ?? variant.tier.label)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                            if variant.isPrimary {
                                Badge(label: "Primary", filled: true)
                            }
                        }
                        Text(variant.tags.joined(separator: " · "))
                            .font(.caption).foregroundStyle(TP.faint)
                        if isLastSelected {
                            Text("Keep at least one hotel").font(.caption).foregroundStyle(TP.faint)
                        }
                    }
                    Spacer()
                    Text(TP.money(option?.amount) + (option?.estimate == true ? " ~" : ""))
                        .font(.headline)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(option?.label ?? variant.tier.label), \(variant.isSelected ? "selected" : "not selected")")

            HStack(spacing: 18) {
                if !variant.isPrimary {
                    Button("Make primary") { makePrimary(variant) }
                        .font(.subheadline).underline().frame(minHeight: 44)
                }
                compareHotelButton(variant)
                if let url = option?.linkUrl, let link = URL(string: url) {
                    Link("View on Expedia", destination: link)
                        .font(.subheadline).underline().frame(minHeight: 44)
                }
                Spacer()
            }
            .foregroundStyle(TP.white)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TP.separator, lineWidth: 1))
    }

    private func toggleSelected(_ variant: HotelVariant) {
        if variant.isSelected {
            guard trip.selectedVariants.count > 1 else { return }  // keep at least one
            variant.isSelected = false
            if variant.isPrimary {
                // Primary moves to the first remaining selected variant.
                if let next = trip.selectedVariants.first {
                    next.isPrimary = true
                }
                variant.isPrimary = false
            }
        } else {
            guard trip.selectedVariants.count < 3 else { return }
            variant.isSelected = true
        }
        save()
    }

    private func makePrimary(_ variant: HotelVariant) {
        for v in trip.hotelVariants { v.isPrimary = v.id == variant.id }
        if !variant.isSelected { variant.isSelected = true }
        save()
        markBox(.hotels, status: "picked")
    }

    @ViewBuilder
    private func compareHotelButton(_ variant: HotelVariant) -> some View {
        let picked = CompareActions.isPicked(picks: picks, trip: trip, tier: variant.tier)
        if picked {
            Button("In Compare ✓") {
                _ = CompareActions.toggle(picks: picks, trip: trip, tier: variant.tier, context: context)
            }
            .font(.subheadline).underline().frame(minHeight: 44)
        } else if picks.count >= CompareActions.maxPicks {
            Text("Compare is full (3 max)").font(.subheadline).foregroundStyle(TP.faint).frame(minHeight: 44)
        } else {
            Button("Add to compare") {
                _ = CompareActions.toggle(picks: picks, trip: trip, tier: variant.tier, context: context)
            }
            .font(.subheadline).underline().frame(minHeight: 44)
        }
    }

    // MARK: Lift / Pass box (this trip's lift line + the plan's pass options, read-only)

    private var liftBoxContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pricing = tripPricing, pricing.result.priced {
                if let line = pricing.lines.first(where: { $0.key == "lift" }) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label).font(.body)
                            Text(line.detail).font(.caption).foregroundStyle(TP.faint)
                        }
                        Spacer()
                        Text(TP.money(line.amount) + (line.estimate ? " ~" : ""))
                            .font(.body.bold()).monospacedDigit()
                    }
                }
                if plan.pass.program != nil {
                    Text("How the pass maths lands across your trips — the cheapest option is applied automatically:")
                        .font(.caption).foregroundStyle(TP.faint)
                    ForEach(plan.pass.options, id: \.key) { option in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(option.label).font(.body)
                                    if option.recommended {
                                        Badge(label: "Recommended", filled: true)
                                    }
                                }
                                Text(option.detail).font(.caption).foregroundStyle(TP.faint)
                            }
                            Spacer()
                            Text(TP.money(option.amount) + (option.estimate ? " ~" : ""))
                                .font(.body.bold()).monospacedDigit()
                        }
                    }
                    Text(plan.pass.note).font(.caption).foregroundStyle(TP.dim)
                    if let urlString = plan.pass.linkUrl, let url = URL(string: urlString) {
                        Link(plan.pass.linkLabel ?? "Epic Pass", destination: url)
                            .font(.subheadline).underline().frame(minHeight: 44)
                    }
                }
            } else {
                Text("Lift pricing arrives with destination pricing.")
                    .font(.subheadline).foregroundStyle(TP.faint)
            }
            boxButtons(.lift, skippable: true)
        }
    }

    // MARK: Gear box

    private var gearBoxContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result = tripPricing?.result, !result.gearOptions.isEmpty {
                ForEach(result.gearOptions) { option in
                    let isChosen = result.chosenGearKey == option.key
                    Button {
                        trip.gear = GearChoice(rawValue: option.key) ?? .auto
                        save()
                        markBox(.gear, status: "picked")
                    } label: {
                        HStack {
                            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label).font(.body)
                                Text(option.detail).font(.caption).foregroundStyle(isChosen ? TP.black.opacity(0.6) : TP.faint)
                            }
                            Spacer()
                            Text(TP.money(option.amount) + (option.estimate ? " ~" : ""))
                                .monospacedDigit()
                        }
                        .padding(12)
                        .frame(minHeight: 56)
                        .background(isChosen ? TP.white : Color.clear)
                        .foregroundStyle(isChosen ? TP.black : TP.white)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isChosen ? TP.white : TP.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Text("“Auto” picks the cheapest, excluding premium rentals. Set explicitly here to override.")
                    .font(.caption).foregroundStyle(TP.faint)
            } else {
                Text("Gear pricing arrives with destination pricing.")
                    .font(.subheadline).foregroundStyle(TP.faint)
            }
            boxButtons(.gear, skippable: true)
        }
    }

    // MARK: Notes & warnings

    @ViewBuilder
    private var notesSection: some View {
        if let pricing = tripPricing, !pricing.warnings.isEmpty || !pricing.result.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Good to know")
                ForEach(pricing.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(TP.white)
                }
                ForEach(pricing.result.notes, id: \.self) { note in
                    Text("· \(note)").font(.subheadline).foregroundStyle(TP.dim)
                }
            }
        }
    }

    // MARK: Breakdown (only place it exists)

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Breakdown")
            if let pricing = tripPricing, pricing.result.priced {
                ForEach(pricing.lines) { line in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label).font(.body)
                            Text(line.detail).font(.caption).foregroundStyle(TP.faint)
                            if let urlString = line.linkUrl, let url = URL(string: urlString), let label = line.linkLabel {
                                Link(label, destination: url)
                                    .font(.caption).underline()
                                    .frame(minHeight: 32)
                            }
                        }
                        Spacer()
                        Text(TP.money(line.amount) + (line.estimate ? " ~" : ""))
                            .font(.body.bold())
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    Divider().background(TP.separator)
                }
                Text("Prices: \(pricing.result.sourceLabel), checked \(pricing.result.checkedAt). ~ = estimate.")
                    .font(.caption).foregroundStyle(TP.faint)
            } else {
                Text(tripPricing?.result.notes.first ?? "Not priced yet — this trip type or place isn't in the researched dataset.")
                    .font(.subheadline).foregroundStyle(TP.dim)
            }
        }
    }

    // MARK: Searchable sheets

    private var typeSheet: some View {
        SearchableSheet(
            title: "Trip type",
            items: catalog.tripTypes.map { (id: $0.id, label: $0.label, detail: $0.blurb) },
            selectedID: trip.tripTypeID
        ) { id in
            trip.tripTypeID = id
            showTypeSheet = false
            clearBoxes([.flights, .hotels, .lift, .gear])
            save()
        }
    }

    private var destinationSheet: some View {
        SearchableSheet(
            title: "Destination",
            items: catalog.destinations.filter { $0.tripTypeID == trip.tripTypeID }
                .map { (id: $0.id, label: "\($0.name), \($0.state)", detail: "Social \($0.socialScore) · Snow \($0.snowScore)") },
            selectedID: trip.destinationID ?? ""
        ) { id in
            trip.destinationID = id
            trip.customDestinationName = nil
            showDestinationSheet = false
            clearBoxes([.flights, .hotels, .lift, .gear])
            save()
        }
    }
}

/// Searchable single-select sheet used for trip type + destination.
struct SearchableSheet: View {
    let title: String
    let items: [(id: String, label: String, detail: String)]
    let selectedID: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.filter { query.isEmpty || $0.label.lowercased().contains(query.lowercased()) }, id: \.id) { item in
                    Button {
                        onPick(item.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label).foregroundStyle(TP.white)
                                Text(item.detail).font(.caption).foregroundStyle(TP.faint)
                            }
                            Spacer()
                            if item.id == selectedID {
                                Image(systemName: "checkmark").foregroundStyle(TP.white)
                            }
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .tpBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
