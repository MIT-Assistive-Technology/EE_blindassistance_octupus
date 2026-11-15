import Foundation

enum Stats {
    enum Log {
        static let pathInterval = 0.01
    }

    enum Length {
        static let normal = 0.70
        static let minimum = 0.30
        static let maximum = 1.20
    }

    enum Steps {
        static let minimumGap = 0.28
        static let maximumFrequency = 3.5
        static let prominenceScale = 0.55
        static let smoothSeconds = 0.12
        static let levelWindow = 2.0
        static let minimumLevel = 1.2
    }

    enum Heading {
        static let initial = 0.0
        static let forwardOffset = 0.0
        static let gyroBias = 0.0
        static let compassBlend = 0.004
        static let turnSmooth = 0.35
        static let turnCommit = 1.30
        static let turnSettle = 0.45
        static let turnReversal = 0.30
        static let turnSnap = 40.0
        static let minimumMagneticAccuracy = 2.0
        static let expectedField = 50.0
        static let disturbanceRatio = 0.4
        static let useMagnetometer = true
        static let turnStart = 0.7
        static let turnEnd = 0.3
        static let minimumTurn = 0.4
        static let minimumTurnDuration = 0.15
    }

    enum Walk {
        static let stepsBeforeTurn = 3
        static let stepsAfterTurn = 2
        static let turnGap = 2.2
        static let turnSnap = 45.0
        static let pacePeriod = 0.60
        static let paceCap = 1.20
        static let paceMin = 0.25
        static let paceMax = 1.80
        static let coefficient = 0.33
    }

    enum Path {
        static let gravity = 9.80665
        static let initialEast = 0.0
        static let initialNorth = 0.0
        static let gapReset = 0.25
        static let maximumDelta = 0.05
        static let biasWindow = 1.5
        static let pointSpacing = 0.1
    }

    enum Stationary {
        static let window = 0.45
        static let accelerationVariance = 0.2
        static let gyroscopeLimit = 0.3
        static let minimumConfidence = 0.85
    }

    enum Cadence {
        static let intercept = 0.35
        static let slope = 0.16
    }

    enum Weinberg {
        static let coefficient = 0.36
    }

    enum Attitude {
        static let complementaryGain = 1.2
        static let mahonyProportional = 0.6
        static let mahonyIntegral = 0.02
        static let gravityTolerance = 2.0
        static let magnetometerGain = 0.2
    }

    enum Kalman {
        static let accelerationNoise = 0.8
        static let headingProcessNoise = 0.02
        static let biasProcessNoise = 1e-4
        static let stepLengthVariance = 0.05
        static let gyroHeadingVariance = 0.04
        static let compassVariance = 0.08
        static let stillVelocityVariance = 0.02
        static let initialPositionVariance = 0.5
        static let initialVelocityVariance = 0.3
        static let initialHeadingVariance = 0.4
        static let initialBiasVariance = 0.01
    }

    enum Offline {
        static let windowSteps = 8
        static let overlapSteps = 2
        static let iterations = 6
        static let useHuberOnSteps = true
        static let huberDelta = 0.35
    }

    enum Plot {
        static let gridStartsVisible = true
    }

    static func color(for id: String) -> (Double, Double, Double) {
        switch id {
        case "k2": return (0.95, 0.45, 0.00)
        case "k1": return (0.00, 0.62, 0.35)
        case "c2": return (0.90, 0.25, 0.20)
        default: return (0.50, 0.50, 0.50)
        }
    }
}
