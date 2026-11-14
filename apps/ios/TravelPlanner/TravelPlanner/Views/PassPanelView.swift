import SwiftUI
import SwiftData

/// The Epic Pass decision panel — lives on Trips (More › Passes & tickets
/// deep-links here). Collapsible with remembered state; options at full
/// opacity, the badge alone marks RECOMMENDED. Sleeps to one line when no
/// Epic trips are in the plan.
struct PassPanelView: View {
    let trips: [Trip]
    @Environment(PricingService.self) private var pricing
    @Environment(ViewPrefs.self) private var prefs
    @Query private var profiles: [Profile]
    @Query private var settingsRows: [PlannerSettings]

    private var pass: PricingEngine.PassPlan {
        pricing.plan(trips: trips, settings: settingsRows.first, profile: profiles.first).pass
    }

    var body: some View {
        @Bindable var prefs = prefs
        let plan = pass
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { prefs.passPanelExpanded.toggle() }
            } label: {
                HStack {
                    Text("The Epic Pass decision")
                        .font(.headline)
                        .foregroundStyle(TP.white)
                    Spacer()
                    if plan.program == nil {
                        Text("No Epic trips in plan")
                            .font(.caption)
                            .foregroundStyle(TP.faint)
                    }
                    Image(systemName: prefs.passPanelExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(TP.white)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if prefs.passPanelExpanded, plan.program != nil {
                ForEach(plan.options, id: \.key) { option in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(option.label).font(.body.bold())
                                if option.recommended {
                                    Badge(label: "Recommended", filled: true)
                                }
                            }
                            Text(option.detail).font(.caption).foregroundStyle(TP.dim)
                        }
                        Spacer()
                        Text(TP.money(option.amount) + (option.estimate ? " ~" : ""))
                            .font(.body.bold())
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
                if let saving = savingSentence(plan) {
                    Text(saving).font(.subheadline).foregroundStyle(TP.white)
                }
                Text(plan.note)
                    .font(.caption)
                    .foregroundStyle(TP.dim)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TP.hairline, lineWidth: 1))
                if let urlString = plan.linkUrl, let url = URL(string: urlString) {
                    Link(plan.linkLabel ?? "Epic Pass", destination: url)
                        .font(.subheadline).underline()
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.separator, lineWidth: 1))
    }

    /// "Saves $132 vs separate passes" — the recommendation stated as a sentence.
    private func savingSentence(_ plan: PricingEngine.PassPlan) -> String? {
        guard let rec = plan.options.first(where: \.recommended),
              rec.key == "combined" || rec.key == "full" else { return nil }
        guard let separate = plan.options.first(where: { $0.key == "separate" }),
              separate.amount > rec.amount else { return nil }
        let saving = PricingEngine.round2(separate.amount - rec.amount)
        return "Saves \(TP.money(saving)) vs separate passes"
    }
}
