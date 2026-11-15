import SwiftUI

@main
struct OctopiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { model.start() }
        }
    }
}
