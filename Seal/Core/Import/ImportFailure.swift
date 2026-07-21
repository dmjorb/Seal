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

extension ImportFailure {
    var userReason: String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "来源未返回明确原因。" }
        return trimmed
    }

    var userMessage: String {
        let action = recovery.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty || action == "知道了" {
            return userReason
        }
        return "\(userReason)\n\(action)"
    }
}
