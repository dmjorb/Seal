import Foundation

enum AppExtensionKind: String, Codable, Equatable, Sendable {
    case widget
    case share
    case notificationService
    case unknown
}
