import Foundation

/// Geographic helpers. Two heading conventions are used in this code base:
///  * PDR heading: radians, counter-clockwise from east (what `Sample.heading` produces).
///  * Compass bearing: degrees, clockwise from north (what people and CoreLocation use).
public enum GeoMath {
    public static let earthRadius = 6_371_000.0

    /// Great-circle distance in metres.
    public static func distance(_ a: GeoFix, _ b: GeoFix) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// Initial compass bearing from `a` to `b`, degrees clockwise from north in 0..<360.
    public static func bearing(from a: GeoFix, to b: GeoFix) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return wrapDegrees(atan2(y, x) * 180 / .pi)
    }

    /// East/north offset in metres from `origin` to `fix` (equirectangular, fine for the < 1 km paths we store).
    public static func localOffset(from origin: GeoFix, to fix: GeoFix) -> LocalPoint {
        let meanLat = (origin.latitude + fix.latitude) / 2 * .pi / 180
        let east = (fix.longitude - origin.longitude) * .pi / 180 * earthRadius * cos(meanLat)
        let north = (fix.latitude - origin.latitude) * .pi / 180 * earthRadius
        return LocalPoint(east: east, north: north)
    }

    /// The fix you get by moving `offset` metres east/north from `origin`.
    public static func offset(_ origin: GeoFix, by offset: LocalPoint) -> GeoFix {
        let lat = origin.latitude + offset.north / earthRadius * 180 / .pi
        let lon = origin.longitude + offset.east / (earthRadius * cos(origin.latitude * .pi / 180)) * 180 / .pi
        var fix = origin
        fix.latitude = lat
        fix.longitude = lon
        return fix
    }

    /// Degrees into 0..<360.
    public static func wrapDegrees(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    /// Signed smallest difference `target - current` in degrees, in -180...180.
    public static func signedDelta(from current: Double, to target: Double) -> Double {
        var d = (target - current).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// PDR heading (radians CCW from east) to compass bearing (degrees CW from north).
    public static func compassBearing(fromPDRHeading heading: Double) -> Double {
        wrapDegrees(90 - heading * 180 / .pi)
    }

    /// Compass bearing (degrees CW from north) to PDR heading (radians CCW from east).
    public static func pdrHeading(fromCompassBearing bearing: Double) -> Double {
        HeadingMath.wrap((90 - bearing) * .pi / 180)
    }
}
