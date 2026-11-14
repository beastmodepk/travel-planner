import SwiftUI

/// The design system: exactly two colours — Jet Black #000 and White —
/// with white-at-opacity tones. No accent colour, no light mode, no theme
/// toggle (removed at the owner's order; do not resurrect).
enum TP {
    static let black = Color.black
    static let white = Color.white
    static let dim = Color.white.opacity(0.7)       // secondary text
    static let faint = Color.white.opacity(0.5)     // captions
    static let hairline = Color.white.opacity(0.25)
    static let separator = Color.white.opacity(0.12)
    static let plate = Color.black.opacity(0.45)    // light backing on photos

    /// Softened photo scrim: a hint of shade only — text sits on frosted
    /// glass panels, not on ink, so the picture stays visible.
    static let scrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(0.16), location: 0.55),
            .init(color: .black.opacity(0.34), location: 0.78),
            .init(color: .black.opacity(0.5), location: 1),
        ],
        startPoint: .top, endPoint: .bottom)

    static func money(_ n: Double?) -> String {
        guard let n else { return "Not priced" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: n)) ?? String(format: "$%.2f", n)
    }

    /// "~$1,969" style for estimates and price-froms.
    static func moneyApprox(_ n: Double?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return "~" + (f.string(from: NSNumber(value: n)) ?? String(format: "$%.0f", n))
    }
}

// MARK: - Buttons (exactly three tiers)

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(TP.white.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundStyle(TP.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.clear)
            .foregroundStyle(TP.white.opacity(configuration.isPressed ? 0.7 : 1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(TP.white, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }
}

/// Tertiary: underlined text with a 44pt hit area.
struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .underline()
            .foregroundStyle(TP.white.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Chips & badges

struct Chip: View {
    let label: String
    var selected: Bool = false
    var checkmark: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected && checkmark {
                    Image(systemName: "checkmark").font(.caption.bold())
                }
                Text(label).font(.subheadline.weight(selected ? .bold : .regular))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? TP.white : Color.clear)
            .foregroundStyle(selected ? TP.black : TP.white)
            .overlay(Capsule().stroke(selected ? TP.white : TP.white.opacity(0.4), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct Badge: View {
    let label: String
    var filled: Bool = false
    /// For use on photos — adds the black-60% backing plate.
    var onPhoto: Bool = false

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? TP.white : (onPhoto ? TP.plate : Color.clear))
            .foregroundStyle(filled ? TP.black : TP.white)
            .overlay(Capsule().stroke(filled ? TP.white : TP.hairline, lineWidth: 1))
            .clipShape(Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(TP.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Destination photo header: remote URL (hosted dataset, v1.1+) → bundled
/// verified photo → designed gradient fallback. Never a broken-image icon.
struct DestinationPhoto: View {
    let destination: Destination?
    var height: CGFloat = 220

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.02), .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom)
            if let destination {
                if let urlString = destination.photoURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(destination.photoAsset)
                        .resizable()
                        .scaledToFill()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .overlay(TP.scrim)
        .accessibilityLabel(destination?.photoAlt ?? "")
    }
}

/// Frosted-glass panel for text that sits on a photo: ultra-thin material
/// plus a black wash and a hairline white border, so the picture shows
/// through while white text stays legible. Black + white palette only.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.32))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
    func tpBackground() -> some View {
        background(TP.black).foregroundStyle(TP.white)
    }
}
