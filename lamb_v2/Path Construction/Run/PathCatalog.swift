import Foundation

enum PathCatalog {
    static func makeOnline() -> [any OnlinePath] {
        [
            WalkPath(id: "k2", name: "K2 Walk stride", weinberg: true),
            WalkPath(id: "k1", name: "K1 Walk heading", weinberg: false),
            WeinbergLength()
        ]
    }
}
