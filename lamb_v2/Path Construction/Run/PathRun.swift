import Foundation
import Observation

@Observable
final class PathRun {
    private var online = PathCatalog.makeOnline()
    private var fed = 0
    private var lastDraw = -1.0
    var lines: [PathLine] = []
    var offlineLines: [PathLine] = []

    func reset() {
        for item in online { item.reset() }
        fed = 0
        lastDraw = -1
        lines = []
        offlineLines = []
    }

    func follow(_ samples: [Sample], visible: Set<String>) {
        let added = fed < samples.count
        while fed < samples.count {
            let sample = samples[fed]
            for item in online { item.push(sample) }
            fed += 1
        }
        let stamp = samples.last?.elapsed ?? 0
        guard added, lastDraw < 0 || stamp - lastDraw >= Stats.Path.pointSpacing else { return }
        show(visible)
        lastDraw = stamp
    }

    func show(_ visible: Set<String>) {
        lines = online.filter { visible.contains($0.id) }.map { $0.line() }
    }

    func runOffline(_ samples: [Sample], visible: Set<String>) {
        offlineLines = PathCatalog.makeOffline().filter { visible.contains($0.id) }.map { $0.run(samples) }
    }
}
