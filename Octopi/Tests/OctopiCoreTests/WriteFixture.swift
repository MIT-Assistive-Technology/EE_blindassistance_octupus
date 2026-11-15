import Foundation
import Testing
@testable import OctopiCore

/// Regenerates the sample pack fixture when OCTOPI_WRITE_FIXTURE is set (also copied to docs/sample-pack.json).
@Suite struct FixtureWriter {
    @Test func writeSamplePackWhenAsked() throws {
        guard let target = ProcessInfo.processInfo.environment["OCTOPI_WRITE_FIXTURE"] else { return }
        try PlacePackTests.samplePack().encoded().write(to: URL(fileURLWithPath: target))
    }
}
