import Foundation
import UniformTypeIdentifiers

final class LogFile {
    let url: URL
    private var handle: FileHandle?
    private static let header = "elapsed,kind,qx,qy,qz,qw,ax,ay,az,rx,ry,rz,gx,gy,gz,mx,my,mz,accuracy,steps,distance\n"
    static var readableTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let csv = UTType(filenameExtension: "csv") { types.append(csv) }
        return types
    }

    private init(url: URL, handle: FileHandle) {
        self.url = url
        self.handle = handle
    }

    static func create() -> LogFile? {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = Self.stamp.string(from: Date())
        let token = String(UUID().uuidString.prefix(4))
        let url = folder.appendingPathComponent("imu_\(stamp)_\(token).csv")
        guard FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8)) else { return nil }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return LogFile(url: url, handle: handle)
    }

    func append(_ sample: Sample) {
        let q = sample.quaternion
        let a = sample.deviceUserAcceleration
        let r = sample.deviceRotation
        let g = sample.deviceGravity
        let m = sample.magneticField
        let row = [
            num(sample.elapsed), "path",
            num(q.x), num(q.y), num(q.z), num(q.w),
            num(a.x), num(a.y), num(a.z),
            num(r.x), num(r.y), num(r.z),
            num(g.x), num(g.y), num(g.z),
            num(m.x), num(m.y), num(m.z),
            num(sample.magneticAccuracy),
            num(sample.pedometerSteps), num(sample.pedometerDistance)
        ].joined(separator: ",") + "\n"
        _ = try? handle?.write(contentsOf: Data(row.utf8))
    }

    func close() {
        _ = try? handle?.close()
        handle = nil
    }

    static func newest() -> URL? {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("imu_") && $0.pathExtension == "csv" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    static func load(_ url: URL) -> [Sample] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = text.split(whereSeparator: \.isNewline)
        guard rows.first?.hasPrefix("elapsed,kind,") == true else { return [] }
        var samples: [Sample] = []
        for line in rows.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 21, let elapsed = Double(fields[0]) else { continue }
            let quat = Quat(x: Double(fields[2]) ?? 0, y: Double(fields[3]) ?? 0, z: Double(fields[4]) ?? 0, w: Double(fields[5]) ?? 1)
            let user = Vec3(x: Double(fields[6]) ?? 0, y: Double(fields[7]) ?? 0, z: Double(fields[8]) ?? 0)
            let rotation = Vec3(x: Double(fields[9]) ?? 0, y: Double(fields[10]) ?? 0, z: Double(fields[11]) ?? 0)
            let gravity = Vec3(x: Double(fields[12]) ?? 0, y: Double(fields[13]) ?? 0, z: Double(fields[14]) ?? 0)
            let field = Vec3(x: Double(fields[15]) ?? 0, y: Double(fields[16]) ?? 0, z: Double(fields[17]) ?? 0)
            let world = Sample.world(user: user, rotation: rotation, quaternion: quat)
            let path = fields[1] == "path" || fields[1] == "motion"
            samples.append(Sample(
                elapsed: elapsed,
                isPath: path,
                quaternion: quat,
                deviceUserAcceleration: user,
                deviceRotation: rotation,
                deviceGravity: gravity,
                magneticField: field,
                magneticAccuracy: Double(fields[18]) ?? -1,
                eastAcceleration: path ? world.east : 0,
                northAcceleration: path ? world.north : 0,
                upAcceleration: path ? world.up : 0,
                yawRate: path ? world.yawRate : 0,
                heading: path ? world.heading : 0,
                pedometerSteps: Double(fields[19]) ?? 0,
                pedometerDistance: Double(fields[20]) ?? 0
            ))
        }
        return samples
    }

    private func num(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
