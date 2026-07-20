import Foundation

protocol AnisetteServerStore: Sendable {
    func selectedServerID() async -> String?
    func saveSelectedServerID(_ id: String) async
}

actor UserDefaultsAnisetteServerStore: AnisetteServerStore {
    private let key = "com.mjorb.seal.anisette-v3.selected-server"

    func selectedServerID() async -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func saveSelectedServerID(_ id: String) async {
        UserDefaults.standard.set(id, forKey: key)
    }
}
