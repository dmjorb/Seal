import Foundation

struct SealLogEntry: Codable, Equatable, Identifiable, Sendable {
    enum Category: String, Codable, Sendable {
        case account
        case pairing
        case signing
        case installation
        case renewal
        case system
    }

    enum Level: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    let id: UUID
    let timestamp: Date
    let category: Category
    let level: Level
    let message: String
    let code: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: Category,
        level: Level = .info,
        message: String,
        code: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.code = code
    }
}
