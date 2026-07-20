import Foundation

struct AnisetteServer: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String
}

enum AnisetteServerCatalog {
    static let official: [AnisetteServer] = [
        AnisetteServer(
            id: "sidestore-app",
            url: URL(string: "https://ani.sidestore.app")!,
            displayName: "ani.sidestore.app"
        )
    ]

    static func prioritized(selectedID: String?) -> [AnisetteServer] {
        guard let selectedID,
              let selected = official.first(where: { $0.id == selectedID }) else {
            return official
        }

        return [selected] + official.filter { $0.id != selected.id }
    }
}
