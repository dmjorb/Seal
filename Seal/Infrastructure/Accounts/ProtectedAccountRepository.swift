import Foundation

actor ProtectedAccountRepository: AccountRepository {
    private let fileURL: URL
    private let fileProtector: any FileProtecting
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        fileURL: URL,
        fileProtector: any FileProtecting = CompleteFileProtector()
    ) {
        self.fileURL = fileURL
        self.fileProtector = fileProtector
        encoder.outputFormatting = [.sortedKeys]
    }

    func fetchAll() throws -> [AppleAccountRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([AppleAccountRecord].self, from: data)
            .sorted { $0.lastVerifiedAt > $1.lastVerifiedAt }
    }

    func save(_ account: AppleAccountRecord) throws {
        var accounts = try fetchAll()
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        try write(accounts)
    }

    func delete(id: UUID) throws {
        var accounts = try fetchAll()
        accounts.removeAll { $0.id == id }
        try write(accounts)
    }

    private func write(_ accounts: [AppleAccountRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
        try fileProtector.protect(fileURL)
    }
}
