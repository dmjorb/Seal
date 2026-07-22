import Foundation

actor AppCustomizationStore {
    private let fileURL: URL
    private let protector: any FileProtecting
    private var cache: [String: AppCustomizationPreference]?

    init(fileURL: URL, protector: any FileProtecting = CompleteFileProtector()) {
        self.fileURL = fileURL
        self.protector = protector
    }

    func all() throws -> [String: AppCustomizationPreference] {
        try loadIfNeeded()
        return cache ?? [:]
    }

    func preference(for originalBundleIdentifier: String) throws -> AppCustomizationPreference? {
        try loadIfNeeded()
        return cache?[Self.key(originalBundleIdentifier)]
    }

    func save(_ preference: AppCustomizationPreference) throws {
        try loadIfNeeded()
        cache?[Self.key(preference.originalBundleIdentifier)] = preference
        try persist()
    }

    func remove(originalBundleIdentifier: String) throws {
        try loadIfNeeded()
        cache?.removeValue(forKey: Self.key(originalBundleIdentifier))
        try persist()
    }

    private func loadIfNeeded() throws {
        guard cache == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = [:]
            return
        }
        let data = try Data(contentsOf: fileURL)
        cache = try JSONDecoder().decode([String: AppCustomizationPreference].self, from: data)
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cache ?? [:])
        try data.write(to: fileURL, options: .atomic)
        try protector.protect(fileURL)
    }

    private static func key(_ bundleIdentifier: String) -> String {
        bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
