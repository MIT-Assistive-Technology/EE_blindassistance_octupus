import Foundation

struct HeadingHistory {
    private var items: [(time: Double, heading: Double)] = []

    mutating func reset() { items.removeAll() }

    mutating func add(time: Double, heading: Double) {
        items.append((time, heading))
        let limit = time - Stats.Steps.levelWindow
        while let first = items.first, first.time < limit { items.removeFirst() }
    }

    func heading(at time: Double) -> Double {
        var chosen = items.first?.heading ?? Stats.Heading.initial
        for item in items where item.time <= time { chosen = item.heading }
        return chosen
    }
}
