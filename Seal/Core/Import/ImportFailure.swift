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
        guard trimmed.isEmpty == false else { return Self.unknownReason }
        if Self.looksTechnical(trimmed) { return Self.unknownReason }
        return trimmed
    }

    var userMessage: String {
        let action = recovery.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty || action == "知道了" {
            return "原因：\(userReason)"
        }
        return "原因：\(userReason)\n\n\(action)"
    }

    private static let unknownReason = "失败原因暂时无法确定。Seal 没有收到明确的失败原因，请重新检测环境后再试。"

    private static func looksTechnical(_ text: String) -> Bool {
        let tokens = [
            "NSURLErrorDomain",
            "NSError",
            "Error Domain=",
            "localizedDescription",
            "com.apple.",
            "kCFErrorDomain",
            "SEAL-",
            "Traceback",
            "Exception",
            "{\"",
            "}\n",
            "[NS",
            "(null)",
            "minimuxer"
        ]
        if tokens.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        if text.contains("[") && text.contains("]") {
            return true
        }
        return false
    }
}
