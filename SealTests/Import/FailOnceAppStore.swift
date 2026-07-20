import Foundation
@testable import Seal

actor FailOnceAppStore: AppStore {
    private var records: [AppRecord] = []
    private var shouldFailReplacement = true

    func fetchAll() -> [AppRecord] {
        records
    }

    func save(_ record: AppRecord) {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func delete(id: UUID) {
        records.removeAll { $0.id == id }
    }

    func replaceImportedApp(_ record: AppRecord) throws -> [AppRecord] {
        if shouldFailReplacement {
            shouldFailReplacement = false
            throw AppStoreError.invalidConfiguration
        }
        let replaced = records.filter {
            $0.originalBundleIdentifier == record.originalBundleIdentifier
        }
        records.removeAll {
            $0.originalBundleIdentifier == record.originalBundleIdentifier
        }
        records.append(record)
        return replaced
    }
}
