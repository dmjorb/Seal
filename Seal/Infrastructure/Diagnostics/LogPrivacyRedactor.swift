import Foundation

enum LogPrivacyRedactor {
    static func redact(_ value: String) -> String {
        var redacted = value
        redacted = redactEmails(in: redacted)
        redacted = redactPhoneNumbers(in: redacted)
        redacted = redactLongIdentifiers(in: redacted)
        redacted = redactSecrets(in: redacted)
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

    private static func redactLongIdentifiers(in value: String) -> String {
        let pattern = #"\b[A-Fa-f0-9]{16,}\b"#
        return replaceMatches(in: value, pattern: pattern) { match in
            guard match.count > 8 else { return match }
            return "\(match.prefix(8))…\(match.suffix(4))"
        }
    }

    private static func redactSecrets(in value: String) -> String {
        let pattern = #"(?i)(authToken|token|password|dsid|secret|private_key)\s*[:=]\s*[^\s,;]+"#
        return replaceMatches(in: value, pattern: pattern) { match in
            guard let separator = match.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return "[redacted]"
            }
            return "\(match[..<separator])\(match[separator]) [redacted]"
        }
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
