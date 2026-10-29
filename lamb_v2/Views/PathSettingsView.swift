import Foundation
import Observation
import SwiftUI

struct PathSettingsView: View {
    var settings: PathSettings
    var logging: Bool
    private let online = PathCatalog.makeOnline()
    private let offline = PathCatalog.makeOffline()

    var body: some View {
        NavigationStack {
            List {
                Picker("Mode", selection: Bindable(settings).mode) {
                    Text("Online").tag("online")
                    Text("Offline").tag("offline")
                }
                .disabled(logging)
                Section("Online") {
                    ForEach(online.map { ($0.id, $0.name) }, id: \.0) { item in
                        Toggle(item.1, isOn: binding(item.0))
                    }
                }
                Section("Offline") {
                    ForEach(offline.map { ($0.id, $0.name) }, id: \.0) { item in
                        Toggle(item.1, isOn: binding(item.0))
                    }
                }
                Section("Unavailable") {
                    ForEach(PathCatalog.unavailable) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.name)
                            Text(item.reason).font(.caption).foregroundStyle(.secondary)
                        }
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
    var mode: String { didSet { save() } }
    var showsGrid: Bool { didSet { save() } }
    var visible: Set<String> { didSet { save() } }
    private var storing = false

    init() {
        let defaults = UserDefaults.standard
        mode = defaults.string(forKey: "path.mode") ?? "online"
        showsGrid = defaults.object(forKey: "path.grid") as? Bool ?? Stats.Plot.gridStartsVisible
        if let stored = defaults.stringArray(forKey: "path.visible") {
            visible = Set(stored)
        } else {
            visible = ["a1", "b2", "c2"]
        }
        storing = true
    }

    func set(_ id: String, on: Bool) {
        if on { visible.insert(id) } else { visible.remove(id) }
    }

    private func save() {
        guard storing else { return }
        let defaults = UserDefaults.standard
        defaults.set(mode, forKey: "path.mode")
        defaults.set(showsGrid, forKey: "path.grid")
        defaults.set(Array(visible), forKey: "path.visible")
    }
}
