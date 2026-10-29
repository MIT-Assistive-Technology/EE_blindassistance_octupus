import Foundation

struct GyroIntegrator {
    var heading = Stats.Heading.initial
    private var lastTime: Double?

    mutating func reset() { heading = Stats.Heading.initial; lastTime = nil }

    mutating func push(_ sample: Sample) {
        guard sample.isPath else { return }
        guard let last = lastTime else {
            lastTime = sample.elapsed
            heading = sample.heading
            return
        }
        let dt = sample.elapsed - last
        lastTime = sample.elapsed
        guard dt > 0, dt < Stats.Path.gapReset else { return }
        let step = min(dt, Stats.Path.maximumDelta)
        heading = HeadingMath.wrap(heading + (sample.yawRate - Stats.Heading.gyroBias) * step)
    }
}
