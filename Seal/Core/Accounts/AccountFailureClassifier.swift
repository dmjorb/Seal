import Foundation

enum AccountFailureDisposition: Equatable, Sendable {
    case transient
    case authentication
    case other
}

enum AccountFailureClassifier {
    private static let transientURLCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .dataNotAllowed,
        .secureConnectionFailed,
        .cannotLoadFromNetwork,
        .resourceUnavailable
    ]

    static func disposition(for error: Error) -> AccountFailureDisposition {
        if let urlError = error as? URLError,
           transientURLCodes.contains(urlError.code) {
            return .transient
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           transientURLCodes.contains(URLError.Code(rawValue: nsError.code)) {
            return .transient
        }

        if let failure = error as? ImportFailure {
            return disposition(for: failure)
        }

        let normalized = normalizedText(error)
        if containsTransientSignal(normalized) { return .transient }
        if containsAuthenticationSignal(normalized) { return .authentication }
        return .other
    }

    static func disposition(for failure: ImportFailure) -> AccountFailureDisposition {
        let normalized = "\(failure.title) \(failure.reason) \(failure.recovery) \(failure.code)".lowercased()
        if containsTransientSignal(normalized) || failure.code.hasPrefix("SEAL-ANI-") {
            return .transient
        }

        switch failure.code {
        case "SEAL-AUTH-101", // verification code rejected
             "SEAL-AUTH-102", // credentials/session explicitly rejected
             "SEAL-AUTH-104", // selected Team/session explicitly unavailable
             "SEAL-AUTH-105", // missing local credential or explicit account failure
             "SEAL-AUTH-106", // local Keychain record mismatch
             "SEAL-AUTH-109", // no valid Team
             "SEAL-AUTH-110": // renewal binding missing
            return .authentication
        default:
            break
        }

        if containsAuthenticationSignal(normalized) { return .authentication }
        return .other
    }

    static func transientFailure(from error: Error) -> ImportFailure {
        let nsError = error as NSError
        return ImportFailure(
            title: "无法连接网络",
            reason: "签名需要连接 Apple 服务。请检查网络后重试。\n来源：\(nsError.domain) \(nsError.code)",
            recovery: "重试",
            code: "SEAL-NET-101"
        )
    }

    private static func normalizedText(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code) \(nsError.localizedDescription) \(String(describing: error))".lowercased()
    }

    private static func containsTransientSignal(_ text: String) -> Bool {
        [
            "network", "internet", "offline", "not connected", "timed out", "timeout",
            "cannot connect", "could not connect", "connection lost", "dns", "host",
            "airplane", "飞行模式", "无网络", "网络不可用", "网络连接", "连接超时",
            "服务暂时不可用", "temporarily unavailable", "secure connection", "tls"
        ].contains { text.contains($0) }
    }

    private static func containsAuthenticationSignal(_ text: String) -> Bool {
        [
            "incorrect credentials", "invalid credentials", "unauthorized", "forbidden",
            "authentication failed", "session expired", "session revoked", "login required",
            "密码无效", "账号或密码", "会话已失效", "重新验证", "凭据缺失",
            "keychain 凭据", "验证码无效", "开发团队不可用"
        ].contains { text.contains($0) }
    }
}
