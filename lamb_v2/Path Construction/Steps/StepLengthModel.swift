import Darwin
import Foundation

enum StepLengthModel {
    static func cadence(_ frequency: Double) -> Double {
        let length = Stats.Cadence.intercept + Stats.Cadence.slope * frequency
        return min(max(length, Stats.Length.minimum), Stats.Length.maximum)
    }

    static func weinberg(range: Double, clamped: inout Int) -> Double {
        let raw = Stats.Weinberg.coefficient * pow(max(range, 0), 0.25)
        let length = min(max(raw, Stats.Length.minimum), Stats.Length.maximum)
        if length != raw { clamped += 1 }
        return length
    }
}
