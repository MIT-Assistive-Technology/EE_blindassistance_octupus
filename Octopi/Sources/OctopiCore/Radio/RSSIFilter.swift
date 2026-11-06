import Foundation

/// Smooths noisy RSSI readings from one beacon and estimates range and trend.
///
/// Pipeline: clip outliers against the running estimate, take the median of a short window,
/// then exponentially smooth. Trend is a least-squares slope over the last `trendWindow` seconds.
public struct RSSIFilter: Sendable {
    public struct Config: Sendable {
        public var windowSize = 7
        public var smoothing = 0.3
        /// Readings further than this (dB) from the estimate are clipped toward it.
        public var outlierClip = 15.0
        public var trendWindow = 10.0
        /// RSSI expected at 1 m. Overridden by the beacon's advertised tx power when present.
        public var txPowerAt1m = -59.0
        /// Path-loss exponent: ~2 free space, 2.5–3.5 indoors with bodies in the way.
        public var pathLossExponent = 2.4
        public init() {}
    }

    public var config: Config
    public private(set) var value: Double?
    public private(set) var lastUpdate: Double?
    private var window: [Double] = []
    private var history: [(time: Double, value: Double)] = []

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func reset() {
        value = nil; lastUpdate = nil; window.removeAll(); history.removeAll()
    }

    /// Feed one raw RSSI (dBm) at monotonic time `time` (s). Returns the smoothed value.
    @discardableResult
    public mutating func add(_ raw: Double, at time: Double) -> Double {
        var reading = raw
        if let current = value {
            reading = min(max(reading, current - config.outlierClip), current + config.outlierClip)
        }
        window.append(reading)
        if window.count > config.windowSize { window.removeFirst() }
        let sorted = window.sorted()
        let median = sorted[sorted.count / 2]
        let next = value.map { $0 + (median - $0) * config.smoothing } ?? median
        value = next
        lastUpdate = time
        history.append((time, next))
        while let first = history.first, time - first.time > config.trendWindow { history.removeFirst() }
        return next
    }

    /// Slope in dB/s over the trend window (positive = getting closer). Nil until there are enough points.
    public var slope: Double? {
        guard history.count >= 4 else { return nil }
        let n = Double(history.count)
        let meanT = history.reduce(0) { $0 + $1.time } / n
        let meanV = history.reduce(0) { $0 + $1.value } / n
        var num = 0.0, den = 0.0
        for item in history {
            num += (item.time - meanT) * (item.value - meanV)
            den += (item.time - meanT) * (item.time - meanT)
        }
        guard den > 0 else { return nil }
        return num / den
    }

    /// Log-distance range estimate in metres.
    public func distance(txPower: Double? = nil) -> Double? {
        guard let value else { return nil }
        let reference = txPower ?? config.txPowerAt1m
        return pow(10, (reference - value) / (10 * config.pathLossExponent))
    }

    public static func distance(rssi: Double, txPower: Double, exponent: Double) -> Double {
        pow(10, (txPower - rssi) / (10 * exponent))
    }
}
