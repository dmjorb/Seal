import Foundation

struct ImportFailure: Error, Equatable, Identifiable, Sendable {
    let title: String
    let reason: String
    let recovery: String
    let code: String

    var id: String { code }
}

extension ImportFailure: LocalizedError {
    var errorDescription: String? { title }
    var failureReason: String? { reason }
    var recoverySuggestion: String? { recovery }
}
