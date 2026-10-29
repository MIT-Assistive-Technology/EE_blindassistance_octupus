import Foundation

struct TurnEvent {
    var start: Double
    var end: Double
    var angle: Double
    var confidence: Double
}

final class TurnDetector {
    private var pending = 0.0
    private var sign = 0.0
    private var turning = false
    private var start = 0.0
    private var angle = 0.0
    private var lastTime: Double?
    private(set) var events: [TurnEvent] = []

    func reset() {
        pending = 0; sign = 0; turning = false; start = 0; angle = 0; lastTime = nil; events.removeAll()
    }

    func push(_ sample: Sample) -> TurnEvent? {
        guard sample.isPath else { return nil }
        let rate = sample.yawRate
        let dt: Double
        if let last = lastTime { dt = max(0, sample.elapsed - last) } else { dt = 0 }
        lastTime = sample.elapsed
        let magnitude = abs(rate)
        if !turning {
            if magnitude >= Stats.Heading.turnStart {
                let next = rate >= 0 ? 1.0 : -1.0
                if next == sign { pending += dt } else { sign = next; pending = dt }
                if pending >= Stats.Heading.minimumTurnDuration {
                    turning = true; start = sample.elapsed; angle = 0
                }
            } else { pending = 0 }
            return nil
        }
        angle += rate * min(dt, Stats.Path.maximumDelta)
        guard magnitude <= Stats.Heading.turnEnd else { return nil }
        turning = false
        let duration = sample.elapsed - start
        guard abs(angle) >= Stats.Heading.minimumTurn else { return nil }
        let confidence = duration < 0.35 && abs(angle) > 1.2 ? 0.3 : 0.7
        let event = TurnEvent(start: start, end: sample.elapsed, angle: angle, confidence: confidence)
        events.append(event)
        return event
    }
}
