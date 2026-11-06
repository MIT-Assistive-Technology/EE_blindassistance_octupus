import SwiftUI

/// Every pushed screen is a value so the stack can be popped to Home programmatically.
enum Route: Hashable {
    case places
    case place(UUID)
    case beacons
    case tutorial
    case settings
    case diagnostics
    case simulator
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.setupComplete { HomeView() } else { SetupView() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .places: PlacesView()
                case .place(let id): PlaceDetailView(placeID: id)
                case .beacons: BeaconsView()
                case .tutorial: HapticTutorialView()
                case .settings: SettingsView()
                case .diagnostics: DiagnosticsView()
                case .simulator: SimulatorControlsView()
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { model.navigation != nil }, set: { if !$0 { model.stopNavigation() } })) {
            NavigateView()
        }
        // When guidance ends, go back to Home so the next action is always in the same place.
        .onChange(of: model.navigation == nil) { _, ended in
            if ended { path = NavigationPath() }
        }
        .tint(.accentColor)
        .onAppear {
            // Debug hook: `-open=settings|tutorial|places|beacons` jumps to a screen (used for screenshots).
            guard model.setupComplete, let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-open=") }) else { return }
            switch arg.dropFirst("-open=".count) {
            case "settings": path.append(Route.settings)
            case "tutorial": path.append(Route.tutorial)
            case "places": path.append(Route.places)
            case "beacons": path.append(Route.beacons)
            default: break
            }
        }
    }
}
