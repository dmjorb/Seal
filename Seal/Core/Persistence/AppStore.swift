import Foundation

protocol AppStore: Actor {
    func fetchAll() throws -> [AppRecord]
    func save(_ record: AppRecord) throws
    func replaceImportedApp(_ record: AppRecord) throws -> [AppRecord]
    func delete(id: UUID) throws
}
