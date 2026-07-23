import Foundation

enum AppleServiceFailurePolicy {
    static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return networkCodes.contains(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           let code = URLError.Code(rawValue: nsError.code),
           networkCodes.contains(code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           isNetworkError(underlying) {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return networkFragments.contains(where: message.contains)
    }

    static func networkFailure(
        title: String = "网络不可用",
        reason: String = "当前无法连接 Apple 服务。已保存的 Apple ID 不会受到影响。",
        recovery: String = "网络恢复后重试",
        code: String = "SEAL-NET-101"
    ) -> ImportFailure {
        ImportFailure(
            title: title,
            reason: reason,
            recovery: recovery,
            code: code
        )
    }

    static func shouldRequireReverification(_ failure: ImportFailure) -> Bool {
        switch failure.code {
        case "SEAL-AUTH-102", // credentials rejected
             "SEAL-AUTH-105", // local credentials missing
             "SEAL-AUTH-106": // local credentials mismatch
            return true
        default:
            return false
        }
    }

    static func isTransient(_ failure: ImportFailure) -> Bool {
        failure.code.hasPrefix("SEAL-NET-")
            || failure.code.hasPrefix("SEAL-ANI-")
            || failure.code == "SEAL-CERT-205"
    }

    private static let networkCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .dataNotAllowed,
        .callIsActive,
        .resourceUnavailable
    ]

    private static let networkFragments = [
        "network",
        "timed out",
        "timeout",
        "not connected",
        "offline",
        "cannot connect",
        "could not connect",
        "cannot find host",
        "dns"
    ]
}
