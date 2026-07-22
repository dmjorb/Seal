import Foundation

enum LogPrivacyRedactor {
    static func redact(_ value: String) -> String {
        var redacted = value
        redacted = redactEmails(in: redacted)
        redacted = redactPhoneNumbers(in: redacted)
        redacted = redactSensitiveHeaders(in: redacted)
        redacted = redactSecrets(in: redacted)
        redacted = redactContextualIdentifiers(in: redacted)
        redacted = redactJWTs(in: redacted)
        redacted = redactUUIDs(in: redacted)
        redacted = redactLongTokens(in: redacted)
        redacted = redactLongIdentifiers(in: redacted)
        return redacted
    }

    private static func redactEmails(in value: String) -> String {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        return replaceMatches(in: value, pattern: pattern, options: [.caseInsensitive]) {
            AppleAccountClient.mask($0)
        }
    }

    private static func redactPhoneNumbers(in value: String) -> String {
        let pattern = #"(?<![A-Za-z0-9])\+?[0-9][0-9 \-()]{5,}[0-9](?![A-Za-z0-9])"#
        return replaceMatches(in: value, pattern: pattern) { match in
            AppleAccountClient.mask(match)
        }
    }

    private static func redactSensitiveHeaders(in value: String) -> String {
        let pattern = #"(?im)\b(authorization|proxy-authorization|cookie|set-cookie|x-apple-[a-z0-9-]+|x-anisette-[a-z0-9-]+)\s*:\s*[^\r\n]+"#
        return replaceMatches(in: value, pattern: pattern) { match in
            guard let separator = match.firstIndex(of: ":") else { return "[redacted]" }
            return "\(match[..<separator]): [redacted]"
        }
    }

    private static func redactSecrets(in value: String) -> String {
        let pattern = #"(?i)\b(authToken|token|password|passwd|dsid|secret|private_key|privateKey|session|sessionToken|clientSecret)\b\s*[:=]\s*[^\s,;]+"#
        return replaceMatches(in: value, pattern: pattern) { match in
            guard let separator = match.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return "[redacted]"
            }
            return "\(match[..<separator])\(match[separator]) [redacted]"
        }
    }

    private static func redactContextualIdentifiers(in value: String) -> String {
        let pattern = #"(?i)\b(team(?:\s*id)?|serial|udid|device(?:\s*(?:id|identifier))?|profile(?:\s*uuid)?|provisioning(?:\s*profile)?(?:\s*uuid)?)\b\s*[:=]\s*[\"']?[A-Za-z0-9-]{6,}[\"']?"#
        return replaceMatches(in: value, pattern: pattern) { match in
            guard let separator = match.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return "[redacted]"
            }
            return "\(match[..<separator])\(match[separator]) [redacted]"
        }
    }

    private static func redactJWTs(in value: String) -> String {
        let pattern = #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#
        return replaceMatches(in: value, pattern: pattern) { _ in "[redacted-jwt]" }
    }

    private static func redactUUIDs(in value: String) -> String {
        let pattern = #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        return replaceMatches(in: value, pattern: pattern) { maskIdentifier($0) }
    }

    private static func redactLongTokens(in value: String) -> String {
        let pattern = #"(?<![A-Za-z0-9+/_=-])[A-Za-z0-9+/_-]{32,}={0,2}(?![A-Za-z0-9+/_=-])"#
        return replaceMatches(in: value, pattern: pattern) { maskIdentifier($0) }
    }

    private static func redactLongIdentifiers(in value: String) -> String {
        let pattern = #"\b[A-Fa-f0-9]{16,}\b"#
        return replaceMatches(in: value, pattern: pattern) { maskIdentifier($0) }
    }

    private static func maskIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return "[redacted]" }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }

    private static func replaceMatches(
        in value: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return value
        }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, options: [], range: nsRange).reversed()
        var result = value
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            let replacement = transform(String(result[range]))
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
