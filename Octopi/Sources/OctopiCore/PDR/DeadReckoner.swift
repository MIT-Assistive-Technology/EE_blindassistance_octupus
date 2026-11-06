import Foundation

/// Tunables for the dead reckoner. Step detection and heading integration are tuned in `Stats`
/// (shared with the IMU test app); these only govern what Octopi adds on top.
public struct PDRConfig: Sendable {
    public enum StepLengthSource: Sendable { case fixed, cadence }
    public enum HeadingSource: Sendable {
        /// Device yaw from the IMU test pipeline (phone held pointing forward).
        case device
        /// Device yaw corrected by the estimated walking axis (phone in a pocket).
        case walkingAxis
    }

    public var stepLength: StepLengthSource = .cadence
    public var heading: HeadingSource = .device
    /// Blend gain toward the compass when the magnetometer looks clean.
    public var compassBlend = Stats.Heading.compassBlend
    /// Seconds without a step after which the phone is "not moving".
    public var movingWindow = 3.0
    /// Position error growth: metres of drift per metre walked (typical PDR 2–10%).
    public var driftPerMetre = 0.06
    /// Fixed drift floor in metres.
    public var driftFloor = 0.5
    /// Keep at most this many step records for position look-ups.
    public var historyLimit = 4000

    public init() {}
}

/// One detected step with the position reached after it.
public struct StepRecord: Equatable, Sendable {
    public var time: Double
    public var position: LocalPoint
    /// PDR heading in radians, counter-clockwise from east.
    public var heading: Double
    public var length: Double
}

/// Pedestrian dead reckoning relative to the current anchor.
///
/// Wraps the shared `StepFinder` / `GyroIntegrator` / `HeadingHistory` from the IMU test app
/// and adds an origin, distance bookkeeping, a drift estimate and position-at-time look-up.
public final class DeadReckoner {
    public var config: PDRConfig
    private var finder = StepFinder()
    private var gyro = GyroIntegrator()
    private var history = HeadingHistory()
    private var axis = WalkingAxisEstimator()
    private var clamped = 0

    public private(set) var position = LocalPoint.origin
    public private(set) var distanceSinceReset = 0.0
    public private(set) var stepCount = 0
    public private(set) var steps: [StepRecord] = []
    public private(set) var lastSampleTime: Double?
    public private(set) var lastStepTime: Double?
    private var primed = false

    public init(config: PDRConfig = PDRConfig()) {
        self.config = config
    }

    /// Current heading in radians CCW from east, or nil before the first sample.
    public var heading: Double? {
        guard primed else { return nil }
        switch config.heading {
        case .device: return gyro.heading
        case .walkingAxis: return axis.corrected(deviceHeading: gyro.heading)
        }
    }

    /// Current heading as a compass bearing in degrees, if known.
    public var compassBearing: Double? { heading.map(GeoMath.compassBearing(fromPDRHeading:)) }

    /// Start a new origin here. The heading estimate is kept.
    public func reset() {
        position = .origin
        distanceSinceReset = 0
        stepCount = 0
        steps.removeAll()
        lastStepTime = nil
        finder.reset()
        clamped = 0
    }

    /// Forget everything including the heading (e.g. the app restarted).
    public func resetAll() {
        reset()
        gyro.reset()
        history.reset()
        axis.reset()
        lastSampleTime = nil
        primed = false
    }

    /// Move the origin so that `newOrigin` (expressed in the old frame) becomes (0, 0).
    public func rebase(to newOrigin: LocalPoint) {
        position = position - newOrigin
        steps = steps.map { var s = $0; s.position = s.position - newOrigin; return s }
        distanceSinceReset = 0
    }

    /// Feed one device-motion reading. Returns a record when a step was detected.
    @discardableResult
    public func push(_ motion: MotionSample) -> StepRecord? { push(motion.sample) }

    @discardableResult
    func push(_ sample: Sample) -> StepRecord? {
        guard sample.isPath else { return nil }
        lastSampleTime = sample.elapsed
        gyro.push(sample)
        primed = true
        if sample.magneticIsUsable, config.compassBlend > 0 {
            gyro.heading = HeadingMath.blend(gyro.heading, sample.heading, gain: config.compassBlend)
        }
        history.add(time: sample.elapsed, heading: gyro.heading)
        axis.push(sample)
        guard let mark = finder.push(sample) else { return nil }
        let length: Double
        switch config.stepLength {
        case .fixed: length = Stats.Length.normal
        case .cadence: length = StepLengthModel.cadence(mark.frequency)
        }
        let deviceHeading = history.heading(at: mark.peak)
        let heading = config.heading == .walkingAxis ? axis.corrected(deviceHeading: deviceHeading) : deviceHeading
        axis.stepEnded(at: sample.elapsed)
        let move = HeadingMath.step(length: length, heading: heading)
        position = LocalPoint(east: position.east + move.east, north: position.north + move.north)
        distanceSinceReset += length
        stepCount += 1
        lastStepTime = mark.peak
        let record = StepRecord(time: mark.peak, position: position, heading: heading, length: length)
        steps.append(record)
        if steps.count > config.historyLimit { steps.removeFirst(steps.count - config.historyLimit) }
        return record
    }

    /// True when a step happened within `movingWindow` seconds of `time`.
    public func isMoving(at time: Double) -> Bool {
        guard let last = lastStepTime else { return false }
        return time - last <= config.movingWindow
    }

    /// Estimated 1-sigma position error in metres since the last reset.
    public var driftEstimate: Double {
        config.driftFloor + config.driftPerMetre * distanceSinceReset
    }

    /// Where we were at `time` (interpolated between steps). Used to place a left-behind beacon.
    public func position(at time: Double) -> LocalPoint {
        guard let first = steps.first else { return position }
        if time <= first.time { return .origin }
        for index in 1..<max(steps.count, 1) where steps[index].time >= time {
            let a = steps[index - 1], b = steps[index]
            let span = b.time - a.time
            let t = span > 0 ? (time - a.time) / span : 1
            return LocalPoint(east: a.position.east + (b.position.east - a.position.east) * t,
                              north: a.position.north + (b.position.north - a.position.north) * t)
        }
        return position
    }

    /// Metres walked between two times, from the step records.
    public func distanceWalked(from start: Double, to end: Double) -> Double {
        steps.filter { $0.time > start && $0.time <= end }.reduce(0) { $0 + $1.length }
    }
}
