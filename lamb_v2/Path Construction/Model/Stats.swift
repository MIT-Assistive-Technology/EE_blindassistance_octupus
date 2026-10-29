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
        static let compassBlend = 0.05
        static let minimumMagneticAccuracy = 2.0
        static let expectedField = 50.0
        static let disturbanceRatio = 0.4
        static let useMagnetometer = true
        static let turnStart = 0.7
        static let turnEnd = 0.3
        static let minimumTurn = 0.4
        static let minimumTurnDuration = 0.15
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
        static let coefficient = 0.55
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
        case "a1": return (0.20, 0.45, 0.95)
        case "a2": return (0.00, 0.55, 0.75)
        case "a3": return (0.05, 0.65, 0.55)
        case "b1": return (0.15, 0.35, 0.90)
        case "b2": return (0.10, 0.25, 0.70)
        case "b3": return (0.35, 0.40, 0.90)
        case "c1": return (0.85, 0.45, 0.15)
        case "c2": return (0.90, 0.25, 0.20)
        case "d1": return (0.55, 0.25, 0.75)
        case "d3": return (0.70, 0.20, 0.55)
        case "d4": return (0.45, 0.15, 0.60)
        case "e1": return (0.25, 0.25, 0.30)
        case "e2": return (0.40, 0.40, 0.45)
        case "e3": return (0.55, 0.55, 0.60)
        case "f1": return (0.15, 0.60, 0.30)
        case "g": return (0.10, 0.10, 0.10)
        case "h1": return (0.75, 0.15, 0.15)
        case "h2": return (0.55, 0.10, 0.10)
        default: return (0.50, 0.50, 0.50)
        }
    }
}
