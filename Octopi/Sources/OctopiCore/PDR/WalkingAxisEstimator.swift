import Foundation

/// Estimates the direction of walking from the world-frame horizontal acceleration.
///
/// While walking, horizontal acceleration oscillates mostly along the direction of travel, no
/// matter how the phone sits in a pocket. The principal axis of (east, north) acceleration over
/// a step therefore gives the walking axis up to a 180° ambiguity; we resolve that by staying
/// close to the device heading, and smooth across steps.
///
/// This is the experimental piece behind `PDRConfig.HeadingSource.walkingAxis`; it is meant
/// to be validated with the IMU test app experiments before becoming the default.
public struct WalkingAxisEstimator: Sendable {
    public private(set) var axis: Double?
    public private(set) var confidence = 0.0
    private var sxx = 0.0, syy = 0.0, sxy = 0.0
    private var count = 0
    private var smoothing = 0.3

    public init() {}

    public mutating func reset() {
        axis = nil; confidence = 0; sxx = 0; syy = 0; sxy = 0; count = 0
    }

    mutating func push(_ sample: Sample) {
        let x = sample.eastAcceleration, y = sample.northAcceleration
        sxx += x * x; syy += y * y; sxy += x * y
        count += 1
    }

    /// Called at each step boundary; folds the step's acceleration into the axis estimate.
    public mutating func stepEnded(at time: Double) {
        defer { sxx = 0; syy = 0; sxy = 0; count = 0 }
        guard count >= 5 else { return }
        let trace = sxx + syy
        guard trace > 0 else { return }
        // Principal axis of the 2x2 covariance; angle of the largest eigenvector.
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let det = sxx * syy - sxy * sxy
        let disc = max(0, (trace * trace) / 4 - det).squareRoot()
        let l1 = trace / 2 + disc, l2 = trace / 2 - disc
        let strength = l1 > 0 ? (l1 - l2) / l1 : 0
        guard let previous = axis else {
            axis = HeadingMath.wrap(angle)
            confidence = strength
            return
        }
        // Axis is defined modulo pi; pick the representative nearest the previous estimate.
        var candidate = HeadingMath.wrap(angle)
        if abs(HeadingMath.wrap(candidate - previous)) > .pi / 2 { candidate = HeadingMath.wrap(candidate + .pi) }
        axis = HeadingMath.blend(previous, candidate, gain: smoothing)
        confidence = confidence * (1 - smoothing) + strength * smoothing
    }

    /// The device heading corrected onto the walking axis, choosing the axis direction closest to the device heading.
    public func corrected(deviceHeading: Double) -> Double {
        guard let axis, confidence > 0.5 else { return deviceHeading }
        let forward = axis
        let backward = HeadingMath.wrap(axis + .pi)
        return abs(HeadingMath.wrap(forward - deviceHeading)) <= abs(HeadingMath.wrap(backward - deviceHeading)) ? forward : backward
    }
}
