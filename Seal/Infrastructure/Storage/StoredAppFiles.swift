import Foundation

struct StoredAppFiles: Codable, Equatable, Sendable {
    let ipaRelativePath: String
    let iconRelativePath: String?
}
