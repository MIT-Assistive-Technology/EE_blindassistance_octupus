import Foundation
import Testing
@testable import OctopiCore

@Suite struct GeoMathTests {
    let origin = GeoFix(latitude: 42.36, longitude: -71.09, horizontalAccuracy: 5, timestamp: Date())

    @Test func oneDegreeOfLatitudeIsAboutOneHundredElevenKilometres() {
        var b = origin; b.latitude += 1
        #expect(approx(GeoMath.distance(origin, b), 111_195, tolerance: 200))
    }

    @Test func bearingsFollowCompassConvention() {
        var n = origin; n.latitude += 0.001
        var e = origin; e.longitude += 0.001
        #expect(approx(GeoMath.bearing(from: origin, to: n), 0, tolerance: 0.5))
        #expect(approx(GeoMath.bearing(from: origin, to: e), 90, tolerance: 0.5))
    }

    @Test func localOffsetRoundTrips() {
        let moved = GeoMath.offset(origin, by: LocalPoint(east: 120, north: -45))
        let back = GeoMath.localOffset(from: origin, to: moved)
        #expect(approx(back.east, 120, tolerance: 0.05))
        #expect(approx(back.north, -45, tolerance: 0.05))
        #expect(approx(GeoMath.distance(origin, moved), 128.16, tolerance: 0.2))
    }

    @Test func headingConversions() {
        #expect(approx(GeoMath.compassBearing(fromPDRHeading: 0), 90, tolerance: 1e-9))
        #expect(approx(GeoMath.compassBearing(fromPDRHeading: .pi / 2), 0, tolerance: 1e-9))
        #expect(approx(GeoMath.compassBearing(fromPDRHeading: .pi), 270, tolerance: 1e-9))
        #expect(approx(GeoMath.pdrHeading(fromCompassBearing: 270), .pi, tolerance: 1e-9) || approx(GeoMath.pdrHeading(fromCompassBearing: 270), -.pi, tolerance: 1e-9))
        #expect(GeoMath.signedDelta(from: 350, to: 10) == 20)
        #expect(GeoMath.signedDelta(from: 10, to: 350) == -20)
        #expect(GeoMath.wrapDegrees(-90) == 270)
    }

    @Test func localPointMaths() {
        let a = LocalPoint(east: 0, north: 0), b = LocalPoint(east: 3, north: 4)
        #expect(a.distance(to: b) == 5)
        #expect(approx(a.heading(to: LocalPoint(east: 0, north: 1)), .pi / 2, tolerance: 1e-9))
        #expect((b - a) == b)
        #expect((a + b) == b)
    }
}
