import Foundation

public enum ProximityZone: String, Codable, Sendable, Comparable {
    case here, near, close, far, lost
    private var rank: Int { switch self { case .here: 0; case .near: 1; case .close: 2; case .far: 3; case .lost: 4 } }
    public static func < (lhs: ProximityZone, rhs: ProximityZone) -> Bool { lhs.rank < rhs.rank }

    public var spoken: String {
        switch self {
        case .here: "right here"
        case .near: "very close"
        case .close: "close"
        case .far: "far"
        case .lost: "out of range"
        }
    }
}

public enum ProximityTrend: String, Codable, Sendable {
    case approaching, steady, receding, unknown
}

public struct ProximityEstimate: Equatable, Sendable {
    public var zone: ProximityZone
    public var trend: ProximityTrend
    /// Estimated metres, nil when lost.
    public var distance: Double?
    /// Seconds between haptic pulses: faster as you get closer (the "ADF" behaviour).
    public var pulseInterval: Double
}

/// Turns a filtered RSSI into a zone, trend and pulse rate.
public struct ProximityEstimator: Sendable {
    public struct Config: Sendable {
        public var hereMetres = 1.2
        public var nearMetres = 3.0
        public var closeMetres = 8.0
        /// Seconds without a reading before the beacon is "lost".
        public var lostAfter = 10.0
        /// dB/s beyond which the trend is reported as approaching/receding.
        public var trendThreshold = 0.4
        public var fastestPulse = 0.25
        public var slowestPulse = 2.0
        public init() {}
    }

    public var config: Config
    public init(config: Config = Config()) { self.config = config }

    public func estimate(from filter: RSSIFilter, txPower: Double?, now: Double) -> ProximityEstimate {
        guard let last = filter.lastUpdate, now - last <= config.lostAfter, let distance = filter.distance(txPower: txPower) else {
            return ProximityEstimate(zone: .lost, trend: .unknown, distance: nil, pulseInterval: config.slowestPulse)
        }
        let zone: ProximityZone
        if distance <= config.hereMetres { zone = .here }
        else if distance <= config.nearMetres { zone = .near }
        else if distance <= config.closeMetres { zone = .close }
        else { zone = .far }
        let trend: ProximityTrend
        if let slope = filter.slope {
            if slope >= config.trendThreshold { trend = .approaching }
            else if slope <= -config.trendThreshold { trend = .receding }
            else { trend = .steady }
        } else { trend = .unknown }
        return ProximityEstimate(zone: zone, trend: trend, distance: distance, pulseInterval: pulseInterval(for: distance))
    }

    /// Linear in distance between `hereMetres` (fastest) and `closeMetres` (slowest).
    public func pulseInterval(for distance: Double) -> Double {
        let span = config.closeMetres - config.hereMetres
        let t = min(max((distance - config.hereMetres) / span, 0), 1)
        return config.fastestPulse + (config.slowestPulse - config.fastestPulse) * t
    }
}
