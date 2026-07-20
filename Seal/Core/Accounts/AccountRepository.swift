import Foundation

protocol AccountRepository: Actor {
    func fetchAll() throws -> [AppleAccountRecord]
    func save(_ account: AppleAccountRecord) throws
    func delete(id: UUID) throws
}
