import Foundation

enum FootMount {
    static let slot = UnavailableVariant(id: "f2", name: "F2 Foot mount", reason: "No foot-mounted sensor")
    static var isMounted: Bool { false }
}
