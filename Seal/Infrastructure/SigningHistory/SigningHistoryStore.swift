import Foundation

actor SigningHistoryStore {
    private let fileURL: URL
    private let maximumEntries: Int
    private let fileProtector: any FileProtecting
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL,
        maximumEntries: Int = 1_000,
        fileProtector: any FileProtecting = CompleteFileProtector()
    ) {
        self.fileURL = fileURL
        self.maximumEntries = maximumEntries
        self.fileProtector = fileProtector
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ record: SigningHistoryRecord) throws {
        var values = try read()
        values.append(record)
        values = Array(values.suffix(maximumEntries))
        try write(values)
    }

    func records() throws -> [SigningHistoryRecord] {
        try read().sorted { $0.signedAt > $1.signedAt }
    }

    func records(accountID: UUID) throws -> [SigningHistoryRecord] {
        try records().filter { $0.accountID == accountID }
    }

    func records(appID: UUID) throws -> [SigningHistoryRecord] {
        try records().filter { $0.appID == appID }
    }

    func markDeleted(appID: UUID) throws {
        var values = try read()
        for index in values.indices where values[index].appID == appID {
            values[index].lifecycleStatus = .deleted
        }
        try write(values)
    }

    func clear(accountID: UUID? = nil) throws {
        if let accountID {
            let remaining = try read().filter { $0.accountID != accountID }
            try write(remaining)
            return
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func read() throws -> [SigningHistoryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode(
            [SigningHistoryRecord].self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func write(_ records: [SigningHistoryRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(records).write(to: fileURL, options: .atomic)
        try fileProtector.protect(fileURL)
    }
}
