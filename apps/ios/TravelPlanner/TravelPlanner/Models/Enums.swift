import Foundation

// Raw values intentionally match the web app / dataset JSON so a value means
// the same thing in every client. Do not rename cases without a dataset +
// contracts change.

/// Lifecycle of a trip. Moved manually by the user only — never automatic.
enum TripPhase: String, Codable, CaseIterable, Identifiable {
    case plan, book, enjoy, past
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plan: return "Plan trip"
        case .book: return "Book trip"
        case .enjoy: return "Enjoy trip"
        case .past: return "Past trip"
        }
    }
    var shortLabel: String {
        switch self {
        case .plan: return "Plan"
        case .book: return "Book"
        case .enjoy: return "Enjoy"
        case .past: return "Past"
        }
    }
}

enum TripStyle: String, Codable, CaseIterable, Identifiable {
    case cheap, balanced, expensive, social, snow
    var id: String { rawValue }
}

enum FareClass: String, Codable, CaseIterable, Identifiable {
    case basic, flex
    var id: String { rawValue }
    var label: String { self == .flex ? "Flex" : "Basic" }
}

enum GearChoice: String, Codable, CaseIterable, Identifiable {
    case auto, rent, carry, boots, premiumRent
    var id: String { rawValue }
}

enum HotelTier: String, Codable, CaseIterable, Identifiable {
    case value, comfort, premium
    var id: String { rawValue }
    var label: String {
        switch self {
        case .value: return "Value"
        case .comfort: return "Comfort"
        case .premium: return "Premium"
        }
    }
}

enum WindowSelection: String, Codable, CaseIterable, Identifiable {
    case dec, jan, custom
    var id: String { rawValue }
}

enum HeldPass: String, Codable, CaseIterable, Identifiable {
    case none, epic, ikon, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .epic: return "Epic Pass"
        case .ikon: return "Ikon Pass"
        case .other: return "Other pass"
        }
    }
}

enum SkiLevel: String, Codable, CaseIterable, Identifiable {
    case firstTime = "first-time"
    case beginner, intermediate, advanced, expert
    var id: String { rawValue }
    var label: String {
        switch self {
        case .firstTime: return "First time"
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .expert: return "Expert"
        }
    }
    var hint: String {
        switch self {
        case .firstTime: return "Never skied — yet"
        case .beginner: return "Greens and easy blues"
        case .intermediate: return "Blues all day, some blacks"
        case .advanced: return "Blacks and steeps"
        case .expert: return "Anywhere on the mountain"
        }
    }
}

enum Terrain: String, Codable, CaseIterable, Identifiable {
    case groomers, bowls, steeps, parks, mix
    var id: String { rawValue }
    var label: String {
        switch self {
        case .groomers: return "Groomers & blues"
        case .bowls: return "Bowls"
        case .steeps: return "Steeps & blacks"
        case .parks: return "Parks"
        case .mix: return "A mix of everything"
        }
    }
}

enum TravelStylePref: String, Codable, CaseIterable, Identifiable {
    case cheap, balanced, treat
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cheap: return "Cheap as possible"
        case .balanced: return "Balanced"
        case .treat: return "Treat myself"
        }
    }
    var hint: String {
        switch self {
        case .cheap: return "Every dollar counts"
        case .balanced: return "Smart spends, no splurges"
        case .treat: return "The good stuff"
        }
    }
}

enum Vibe: String, Codable, CaseIterable, Identifiable {
    case social, quiet, mix
    var id: String { rawValue }
    var label: String {
        switch self {
        case .social: return "Social & nightlife"
        case .quiet: return "Quiet & scenery"
        case .mix: return "A mix"
        }
    }
    var hint: String {
        switch self {
        case .social: return "Bars, people, going out"
        case .quiet: return "Calm first, early nights"
        case .mix: return "Depends on the day"
        }
    }
}

enum GearOwned: String, Codable, CaseIterable, Identifiable {
    case ownSkis = "own-skis"
    case ownBoots = "own-boots"
    case rent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ownSkis: return "Own skis & boots"
        case .ownBoots: return "Own boots only"
        case .rent: return "Rent everything"
        }
    }
    var hint: String {
        switch self {
        case .ownSkis: return "Defaults to flying with them"
        case .ownBoots: return "Defaults to renting skis only"
        case .rent: return "Defaults to the cheapest rental"
        }
    }
}

enum GroupSize: String, Codable, CaseIterable, Identifiable {
    case solo, couple, friends, family
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var travellers: Int {
        switch self {
        case .solo: return 1
        case .couple: return 2
        case .friends: return 3
        case .family: return 4
        }
    }
}

enum BrochureStatus: String, Codable, CaseIterable {
    case queued, sent, failed
    var label: String {
        switch self {
        case .queued: return "Queued"
        case .sent: return "Sent"
        case .failed: return "Failed"
        }
    }
}

// MARK: - View preferences (UserDefaults only — display state, never pricing)

enum TripSort: String, CaseIterable, Identifiable {
    case manual, name
    case priceAsc = "price-asc"
    case priceDesc = "price-desc"
    case date
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: return "My order"
        case .name: return "Name A–Z"
        case .priceAsc: return "Price · low to high"
        case .priceDesc: return "Price · high to low"
        case .date: return "Date"
        }
    }
}

enum GallerySort: String, CaseIterable, Identifiable {
    case curated, name
    case priceAsc = "price-asc"
    case priceDesc = "price-desc"
    case snow, social
    var id: String { rawValue }
    var label: String {
        switch self {
        case .curated: return "Featured"
        case .name: return "Name A–Z"
        case .priceAsc: return "Price · low to high"
        case .priceDesc: return "Price · high to low"
        case .snow: return "Best snow"
        case .social: return "Most social"
        }
    }
}

enum HotelSort: String, CaseIterable, Identifiable {
    case price, name
    var id: String { rawValue }
    var label: String { self == .price ? "Price" : "Name" }
}

enum PhaseTab: String, CaseIterable, Identifiable {
    case all, plan, book, enjoy, past
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All trips"
        case .plan: return "Plan trip"
        case .book: return "Book trip"
        case .enjoy: return "Enjoy trip"
        case .past: return "Past trip"
        }
    }
    var phase: TripPhase? {
        switch self {
        case .all: return nil
        case .plan: return .plan
        case .book: return .book
        case .enjoy: return .enjoy
        case .past: return .past
        }
    }
}
