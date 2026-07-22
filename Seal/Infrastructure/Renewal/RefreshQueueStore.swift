import Foundation

actor RefreshQueueStore {
    private struct PersistedQueue: Codable {
        var sessionID: String?
        var items: [RefreshQueueItem]
    }

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
        try read().items
    }

    func replace(with items: [RefreshQueueItem]) throws {
        try write(PersistedQueue(sessionID: nil, items: items))
    }

    /// Prepares work for a persisted batch. A non-nil session ID resumes the
    /// same batch without repeating completed items. Nil always starts a new,
    /// explicit batch (for example, a user-initiated refresh-all operation).
    func prepare(
        with plannedItems: [RefreshQueueItem],
        sessionID: String?
    ) throws -> [RefreshQueueItem] {
        let existing = try read()
        let resumesExistingSession = sessionID != nil && existing.sessionID == sessionID
        let existingByAppID = Self.itemsByAppID(existing.items)
        let prepared = plannedItems.map { planned -> RefreshQueueItem in
            guard resumesExistingSession,
                  let persisted = existingByAppID[planned.appID] else {
                var pending = planned
                pending.state = .pending
                pending.lastErrorCode = nil
                return pending
            }
            if persisted.state == .completed {
                return persisted
            }
            var pending = planned
            pending.state = .pending
            pending.lastErrorCode = nil
            return pending
        }
        try write(PersistedQueue(sessionID: sessionID, items: prepared))
        return prepared.filter { $0.state != .completed }
    }

    func markRunning(appID: UUID) throws {
        try update(appID: appID, state: .running, errorCode: nil)
    }

    func markCompleted(appID: UUID) throws {
        try update(appID: appID, state: .completed, errorCode: nil)
    }

    func reconcileCompleted(appID: UUID, sessionID: String) throws -> Bool {
        var queue = try read()
        guard queue.sessionID == sessionID,
              let index = queue.items.firstIndex(where: { $0.appID == appID }) else {
            return false
        }
        queue.items[index].state = .completed
        queue.items[index].lastErrorCode = nil
        try write(queue)
        return queue.items.allSatisfy { $0.state == .completed }
    }

    func isBatchCompleted(sessionID: String) throws -> Bool {
        let queue = try read()
        guard queue.sessionID == sessionID else { return false }
        return queue.items.allSatisfy { $0.state == .completed }
    }

    func markFailed(appID: UUID, errorCode: String) throws {
        try update(appID: appID, state: .failed, errorCode: errorCode)
    }

    func markPending(appID: UUID) throws {
        try update(appID: appID, state: .pending, errorCode: nil)
    }

    func removeCompleted() throws {
        var queue = try read()
        queue.items.removeAll { $0.state == .completed }
        try write(queue)
    }

    private func update(
        appID: UUID,
        state: RefreshQueueItem.State,
        errorCode: String?
    ) throws {
        var queue = try read()
        guard let index = queue.items.firstIndex(where: { $0.appID == appID }) else { return }
        queue.items[index].state = state
        queue.items[index].lastErrorCode = errorCode
        try write(queue)
    }

    private func read() throws -> PersistedQueue {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersistedQueue(sessionID: nil, items: [])
        }
        let data = try Data(contentsOf: fileURL)
        if let queue = try? decoder.decode(PersistedQueue.self, from: data) {
            return Self.normalized(queue)
        }
        return Self.normalized(
            PersistedQueue(
                sessionID: nil,
                items: try decoder.decode([RefreshQueueItem].self, from: data)
            )
        )
    }

    private static func normalized(_ queue: PersistedQueue) -> PersistedQueue {
        let byAppID = itemsByAppID(queue.items)
        var emittedAppIDs = Set<UUID>()
        let ordered = queue.items.compactMap { item -> RefreshQueueItem? in
            guard let selected = byAppID[item.appID],
                  selected.id == item.id,
                  emittedAppIDs.insert(item.appID).inserted else {
                return nil
            }
            return selected
        }
        return PersistedQueue(sessionID: queue.sessionID, items: ordered)
    }

    private static func itemsByAppID(
        _ items: [RefreshQueueItem]
    ) -> [UUID: RefreshQueueItem] {
        items.reduce(into: [:]) { result, item in
            guard let current = result[item.appID] else {
                result[item.appID] = item
                return
            }
            // A completed marker is authoritative. Otherwise keep the latest
            // occurrence so a partially-written legacy queue can still resume.
            if current.state != .completed || item.state == .completed {
                result[item.appID] = item
            }
        }
    }

    private func write(_ queue: PersistedQueue) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(queue).write(to: fileURL, options: .atomic)
        try fileProtector.protect(fileURL)
    }
}
