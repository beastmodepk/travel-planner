import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [Profile]
    @Query private var picks: [ComparePick]
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Group {
            if let profile = profiles.first, profile.onboarded {
                tabs
            } else {
                OnboardingView()
            }
        }
        .tpBackground()
    }

    private var tabs: some View {
        @Bindable var nav = navigation
        return TabView(selection: $nav.selectedTab) {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "compass.drawing") }
                .tag(AppNavigation.Tab.explore)
            TripsView()
                .tabItem { Label("Trips", systemImage: "suitcase") }
                .tag(AppNavigation.Tab.trips)
            CompareView()
                .tabItem { Label("Compare", systemImage: "rectangle.split.3x1") }
                .tag(AppNavigation.Tab.compare)
                .badge(picks.count > 0 ? picks.count : 0)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(AppNavigation.Tab.more)
        }
        .tint(TP.white)
    }
}
