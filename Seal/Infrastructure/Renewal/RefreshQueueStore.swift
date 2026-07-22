import Foundation

actor RefreshQueueStore {
    private let fileURL: URL
    private let fileProtector: any FileProtecting
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL,
        fileProtector: any FileProtecting = CompleteFileProtector()
    ) {
        self.fileURL = fileURL
        self.fileProtector = fileProtector
        encoder.outputFormatting = [.sortedKeys]
    }

    func load() throws -> [RefreshQueueItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode(
            [RefreshQueueItem].self,
            from: Data(contentsOf: fileURL)
        )
    }

    func replace(with items: [RefreshQueueItem]) throws {
        try write(items)
    }

    func markRunning(appID: UUID) throws {
        try update(appID: appID, state: .running, errorCode: nil)
    }

    func markCompleted(appID: UUID) throws {
        try update(appID: appID, state: .completed, errorCode: nil)
    }

    func markFailed(appID: UUID, errorCode: String) throws {
        try update(appID: appID, state: .failed, errorCode: errorCode)
    }

    func markPending(appID: UUID) throws {
        try update(appID: appID, state: .pending, errorCode: nil)
    }

    func removeCompleted() throws {
        try write(try load().filter { $0.state != .completed })
    }

    private func update(
        appID: UUID,
        state: RefreshQueueItem.State,
        errorCode: String?
    ) throws {
        var items = try load()
        guard let index = items.firstIndex(where: { $0.appID == appID }) else { return }
        items[index].state = state
        items[index].lastErrorCode = errorCode
        try write(items)
    }

    private func write(_ items: [RefreshQueueItem]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(items).write(to: fileURL, options: .atomic)
        try fileProtector.protect(fileURL)
    }
}
