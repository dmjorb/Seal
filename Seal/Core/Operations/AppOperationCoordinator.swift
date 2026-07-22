import Foundation

actor AppOperationCoordinator {
    enum Kind: Equatable, Sendable {
        case importing
        case signing
        case installing
        case refreshing
        case selfReplacing
        case cleaning
    }

    enum AcquisitionError: Error, Equatable, Sendable {
        case busy
    }

    final class Lease: Sendable {
        let id: UUID
        let appID: UUID?
        let kind: Kind
        private let coordinator: AppOperationCoordinator

        fileprivate init(
            id: UUID,
            appID: UUID?,
            kind: Kind,
            coordinator: AppOperationCoordinator
        ) {
            self.id = id
            self.appID = appID
            self.kind = kind
            self.coordinator = coordinator
        }

        func release() async {
            await coordinator.release(token: id)
        }

        deinit {
            let coordinator = coordinator
            let token = id
            Task {
                await coordinator.release(token: token)
            }
        }
    }

    private struct Entry: Sendable {
        let appID: UUID?
        let kind: Kind
    }

    private var leases: [UUID: Entry] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func acquire(appID: UUID?, kind: Kind) throws -> Lease {
        try Task.checkCancellation()

        if let appID {
            guard leases.values.contains(where: { $0.appID == nil }) == false,
                  leases.values.contains(where: { $0.appID == appID }) == false else {
                throw AcquisitionError.busy
            }
        } else if kind == .cleaning {
            guard leases.values.contains(where: { $0.appID == nil }) == false else {
                throw AcquisitionError.busy
            }
        } else {
            guard leases.isEmpty else { throw AcquisitionError.busy }
        }

        let lease = Lease(
            id: UUID(),
            appID: appID,
            kind: kind,
            coordinator: self
        )
        leases[lease.id] = Entry(appID: appID, kind: kind)
        return lease
    }

    func withLease<Value: Sendable>(
        appID: UUID?,
        kind: Kind,
        operation: @Sendable (Lease) async throws -> Value
    ) async throws -> Value {
        let lease = try acquire(appID: appID, kind: kind)
        defer { release(token: lease.id) }
        return try await operation(lease)
    }

    func waitUntilIdle() async {
        guard leases.isEmpty == false else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func isBusy(appID: UUID) -> Bool {
        leases.values.contains { lease in
            lease.appID == nil || lease.appID == appID
        }
    }

    func snapshot() -> Set<UUID> {
        Set(leases.values.compactMap(\.appID))
    }

    func associate(_ lease: Lease, with appID: UUID) throws {
        guard let entry = leases[lease.id] else { throw AcquisitionError.busy }
        if entry.appID == appID { return }
        guard leases.values.contains(where: { $0.appID == appID }) == false else {
            throw AcquisitionError.busy
        }
        leases[lease.id] = Entry(appID: appID, kind: entry.kind)
    }

    private func release(token: UUID) {
        guard leases.removeValue(forKey: token) != nil else { return }
        guard leases.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
