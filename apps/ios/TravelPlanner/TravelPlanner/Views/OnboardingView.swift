import SwiftUI
import SwiftData

/// First-run gate: 10 questions, Atomic-Habits style. Single-select answers
/// auto-advance (7 of 10); name, airport and multi-select terrain wait for
/// Continue. Step 1 carries a prominent Skip. The payoff screen shows the
/// seeded, already-priced trips — value within ~30 seconds by either path.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(PricingService.self) private var pricing
    @Query(sort: \Trip.sortIndex) private var trips: [Trip]
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]

    private enum Stage {
        case questions, payoff
    }

    @State private var stage: Stage = .questions
    @State private var step = 0
    @State private var skipped = false

    // Answers (defaults mirror the web's DEFAULT_PROFILE).
    @State private var name = ""
    @State private var airport = "BOS"
    @State private var level: SkiLevel = .intermediate
    @State private var terrain: Set<Terrain> = [.mix]
    @State private var travelStyle: TravelStylePref = .balanced
    @State private var vibe: Vibe = .mix
    @State private var remoteWork = false
    @State private var gearOwned: GearOwned = .rent
    @State private var passHeld: HeldPass = .none
    @State private var group: GroupSize = .solo

    private let stepCount = 10

    var body: some View {
        Group {
            switch stage {
            case .questions: questionFlow
            case .payoff: payoff
            }
        }
        .tpBackground()
    }

    // MARK: Questions

    private var questionFlow: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STEP \(step + 1) OF \(stepCount)")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(TP.faint)
                Spacer()
                Button("Skip for now") { skip() }
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(TP.white)
                    .frame(minHeight: 44)
            }
            // 10 progress segments.
            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? TP.white : TP.white.opacity(0.2))
                        .frame(height: 3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(stepCount)")

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 28)
            }

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(TertiaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            Text("TRAVEL PLANNER")
                .font(.caption.weight(.semibold)).tracking(3).foregroundStyle(TP.faint)
            heading("What's your name?", "So Travel Planner can greet you properly — for any trip, not just ski.")
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(minHeight: 52)
            Button("Continue") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            Button("Skip — show me trips") { skip() }
                .buttonStyle(SecondaryButtonStyle())
        case 1:
            heading("Your home airport?", "Flights are priced from here. Three-letter code.")
            TextField("BOS", text: $airport)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: airport) { _, new in
                    airport = String(new.uppercased().filter(\.isLetter).prefix(5))
                    if airport.count == 3 { next() }
                }
            Button("Continue") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(airport.count < 3)
                .opacity(airport.count < 3 ? 0.4 : 1)
        case 2:
            heading("If you ski, how do you ski?", "Only used for ski trips (West Coast & Japan). Other trip types ignore it.")
            optionList(SkiLevel.allCases, current: level) { level = $0; next() }
        case 3:
            heading("Terrain you love (for ski)", "Pick any — ski resorts that match get flagged for you.")
            FlowChips(
                options: Terrain.allCases.map { (value: $0, label: $0.label) },
                selected: terrain
            ) { terrain = $0 }
            Button("Continue") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(terrain.isEmpty)
                .opacity(terrain.isEmpty ? 0.4 : 1)
        case 4:
            heading("Your travel style", "Sets the default trip style — changeable per trip.")
            optionList(TravelStylePref.allCases, current: travelStyle) { travelStyle = $0; next() }
        case 5:
            heading("Trip vibe", "Social trips default to the Best Social style.")
            optionList(Vibe.allCases, current: vibe) { vibe = $0; next() }
        case 6:
            heading("Work remotely on trips?", "If yes, we'll flag lodging that can't support workdays.")
            optionRow(label: "Yes — need a proper room & wifi", selected: remoteWork) { remoteWork = true; next() }
            optionRow(label: "No — fully off", selected: !remoteWork) { remoteWork = false; next() }
        case 7:
            heading("Your ski gear", "Sets the default gear choice on ski trips only.")
            optionList(GearOwned.allCases, current: gearOwned) { gearOwned = $0; next() }
        case 8:
            heading("Ski passes you hold", "Held passes price covered lift days at $0 on ski trips.")
            optionList(HeldPass.allCases, current: passHeld, label: \.label) { passHeld = $0; next() }
        default:
            heading("Typical group", "Sets the default traveller count.")
            optionList(GroupSize.allCases, current: group, label: \.label) { group = $0 }
            Button("Start planning") { finish() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private func heading(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold()).foregroundStyle(TP.white)
            Text(sub).font(.subheadline).foregroundStyle(TP.dim)
        }
    }

    private func optionRow(label: String, hint: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.body)
                Spacer()
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(selected ? TP.black.opacity(0.6) : TP.faint)
                }
                if selected {
                    Image(systemName: "checkmark").font(.subheadline.bold())
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(selected ? TP.white : Color.clear)
            .foregroundStyle(selected ? TP.black : TP.white)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? TP.white : TP.hairline, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func optionList<T: Identifiable & Equatable>(
        _ options: [T], current: T, label: KeyPath<T, String>? = nil, choose: @escaping (T) -> Void
    ) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                optionRow(
                    label: label.map { option[keyPath: $0] } ?? String(describing: option),
                    selected: option == current
                ) { choose(option) }
            }
        }
    }

    // MARK: Flow control

    private func next() { step = min(step + 1, stepCount - 1) }

    private func builtProfile() -> Profile {
        let p = Profile()
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.homeAirport = airport.isEmpty ? "BOS" : airport
        p.level = level
        p.terrain = Array(terrain)
        p.travelStyle = travelStyle
        p.vibe = vibe
        p.remoteWork = remoteWork
        p.gearOwned = gearOwned
        p.passHeld = passHeld
        p.group = group
        return p
    }

    private func finish() {
        Seeding.seedIfNeeded(context: context, catalog: pricing.catalog, profile: builtProfile(), skipped: false)
        stage = .payoff
    }

    private func skip() {
        skipped = true
        Seeding.seedIfNeeded(context: context, catalog: pricing.catalog, profile: nil, skipped: true)
        stage = .payoff
    }

    // MARK: Payoff

    private var payoff: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Here's your planner\(name.isEmpty ? "" : ", \(name)")")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)
                if skipped {
                    Text("Defaults are in — BOS · Intermediate · Balanced · rent gear. Change any of it anytime in More › Profile.")
                        .font(.subheadline).foregroundStyle(TP.dim)
                } else {
                    Text("Two trips are already priced from your answers. Open either one to tune dates, hotels and gear.")
                        .font(.subheadline).foregroundStyle(TP.dim)
                }
                let plan = pricing.plan(trips: trips, settings: settingsRows.first, profile: profiles.first)
                ForEach(trips) { trip in
                    let destName = trip.destinationID.flatMap { pricing.catalog.destination(id: $0)?.name } ?? trip.customDestinationName ?? ""
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(destName).font(.headline)
                            Text("\(PricingEngine.dateString(trip.startDate)) – \(PricingEngine.dateString(trip.endDate)) · \(trip.activityDays) ski days")
                                .font(.caption).foregroundStyle(TP.faint)
                        }
                        Spacer()
                        Text(TP.money(plan.trips[trip.id]?.total))
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.hairline, lineWidth: 1))
                }
                Text("You're all set — Explore is waiting with every destination.")
                    .font(.subheadline).foregroundStyle(TP.faint)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

/// Wrapping multi-select chips (terrain step).
struct FlowChips<T: Hashable>: View {
    let options: [(value: T, label: String)]
    let selected: Set<T>
    let onChange: (Set<T>) -> Void

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(options, id: \.value) { option in
                Chip(label: option.label, selected: selected.contains(option.value), checkmark: true) {
                    var next = selected
                    if next.contains(option.value) { next.remove(option.value) } else { next.insert(option.value) }
                    onChange(next)
                }
            }
        }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
