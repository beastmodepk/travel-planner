import Foundation
import Observation

/// Sort/filter/tab state. UserDefaults only, by design: this is display
/// state — it never affects pricing, never syncs, and changing it must never
/// invalidate the pricing cache (PricingService.cacheKey excludes it).
@MainActor
@Observable
final class ViewPrefs {
    private let defaults: UserDefaults

    var tripSort: TripSort { didSet { defaults.set(tripSort.rawValue, forKey: Keys.tripSort) } }
    var gallerySort: GallerySort { didSet { defaults.set(gallerySort.rawValue, forKey: Keys.gallerySort) } }
    var tripFilter: String { didSet { defaults.set(tripFilter, forKey: Keys.tripFilter) } }
    var galleryFilter: String { didSet { defaults.set(galleryFilter, forKey: Keys.galleryFilter) } }
    var galleryType: String { didSet { defaults.set(galleryType, forKey: Keys.galleryType) } }
    var hotelSort: HotelSort { didSet { defaults.set(hotelSort.rawValue, forKey: Keys.hotelSort) } }
    var phaseTab: PhaseTab { didSet { defaults.set(phaseTab.rawValue, forKey: Keys.phaseTab) } }

    private enum Keys {
        static let tripSort = "tp.tripSort"
        static let gallerySort = "tp.gallerySort"
        static let tripFilter = "tp.tripFilter"
        static let galleryFilter = "tp.galleryFilter"
        static let galleryType = "tp.galleryType"
        static let hotelSort = "tp.hotelSort"
        static let phaseTab = "tp.phaseTab"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tripSort = TripSort(rawValue: defaults.string(forKey: Keys.tripSort) ?? "") ?? .manual
        gallerySort = GallerySort(rawValue: defaults.string(forKey: Keys.gallerySort) ?? "") ?? .curated
        tripFilter = defaults.string(forKey: Keys.tripFilter) ?? ""
        galleryFilter = defaults.string(forKey: Keys.galleryFilter) ?? ""
        galleryType = defaults.string(forKey: Keys.galleryType) ?? "all"
        hotelSort = HotelSort(rawValue: defaults.string(forKey: Keys.hotelSort) ?? "") ?? .price
        phaseTab = PhaseTab(rawValue: defaults.string(forKey: Keys.phaseTab) ?? "") ?? .all
        passPanelExpanded = defaults.bool(forKey: Keys.passExpanded)
    }
}
