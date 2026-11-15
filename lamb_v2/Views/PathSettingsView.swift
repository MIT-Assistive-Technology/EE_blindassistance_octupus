import Foundation
import Observation
import SwiftUI

struct PathSettingsView: View {
    var settings: PathSettings
    private let online = PathCatalog.makeOnline()

    var body: some View {
        NavigationStack {
            List {
                Section("Lines") {
                    ForEach(online.map { ($0.id, $0.name) }, id: \.0) { item in
                        Toggle(item.1, isOn: binding(item.0))
                    }
                }
            }
            .navigationTitle("Path lines")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.visible.contains(id) }, set: { settings.set(id, on: $0) })
    }
}

@Observable
final class PathSettings {
    var showsGrid: Bool { didSet { save() } }
    var visible: Set<String> { didSet { save() } }
    private var storing = false
    private static let allowed: Set<String> = ["k1", "k2", "c2"]

    init() {
        let defaults = UserDefaults.standard
        showsGrid = defaults.object(forKey: "path.grid") as? Bool ?? Stats.Plot.gridStartsVisible
        if let saved = defaults.stringArray(forKey: "path.visible") {
            visible = Set(saved).intersection(Self.allowed)
        } else {
            visible = ["k2"]
        }
        if visible.isEmpty { visible = ["k2"] }
        storing = true
    }

    func set(_ id: String, on: Bool) {
        if on { visible.insert(id) } else { visible.remove(id) }
    }

    private func save() {
        guard storing else { return }
        let defaults = UserDefaults.standard
        defaults.set(showsGrid, forKey: "path.grid")
        defaults.set(Array(visible), forKey: "path.visible")
    }
}
