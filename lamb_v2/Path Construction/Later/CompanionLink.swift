import Foundation

protocol CompanionLink: AnyObject {
    func send(samples: [Sample])
}

final class NoCompanion: CompanionLink {
    static let slot = UnavailableVariant(id: "link", name: "Second device", reason: "No companion link")

    func send(samples: [Sample]) {}
}
