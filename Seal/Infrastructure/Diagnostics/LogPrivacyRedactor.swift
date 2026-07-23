import Foundation

enum LogPrivacyRedactor {
    static func redact(_ value: String) -> String {
        var redacted = value
        redacted = redactEmails(in: redacted)
        redacted = redactPhoneNumbers(in: redacted)
        redacted = redactJWTs(in: redacted)
        redacted = redactSensitiveKeyValueFields(in: redacted)
        redacted = redactSensitiveXMLFields(in: redacted)
        redacted = redactUUIDs(in: redacted)
        redacted = redactLongIdentifiers(in: redacted)
        redacted = redactBase64Tokens(in: redacted)
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

    private static func redactJWTs(in value: String) -> String {
        let pattern = #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#
        return replaceMatches(in: value, pattern: pattern) { _ in "[redacted-jwt]" }
    }

    private static func redactSensitiveKeyValueFields(in value: String) -> String {
        let keys = [
            "team(?:\\s*id)?", "serial(?:number)?", "udid", "uuid",
            "profile(?:\\s*uuid)?", "provisioning(?:Profile)?UUID",
            "jwt", "cookie", "authorization", "header", "headers",
            "authToken", "token", "password", "passwd", "dsid", "secret",
            "private[_ -]?key", "clientSecret", "sessionId", "sessionToken",
            "X-Apple-I-MD", "X-Apple-I-MD-M", "X-Apple-I-MD-RINFO",
            "pairing(?:File|Record|Data)?", "escrowBag", "hostId", "systemBUID"
        ].joined(separator: "|")
        let pattern = "(?i)(\\b(?:\(keys))\\b\\s*[：:=]\\s*)([^\\s,;\\]\\}]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: nsRange).reversed()
        var result = value
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let prefixRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(fullRange, with: "\(result[prefixRange])[redacted]")
        }
        return result
    }

    private static func redactSensitiveXMLFields(in value: String) -> String {
        let pattern = #"(?is)(<key>\s*(?:UDID|UUID|SerialNumber|TeamID|ProfileUUID|Authorization|Cookie|Token|Password|EscrowBag|HostID|SystemBUID)\s*</key>\s*<string>)[^<]*(</string>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: nsRange).reversed()
        var result = value
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let suffixRange = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(fullRange, with: "\(result[prefixRange])[redacted]\(result[suffixRange])")
        }
        return result
    }

    private static func redactUUIDs(in value: String) -> String {
        let pattern = #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        return replaceMatches(in: value, pattern: pattern) { match in
            "\(match.prefix(8))…[uuid]"
        }
    }

    private static func redactLongIdentifiers(in value: String) -> String {
        // Covers certificate fingerprints, device identifiers and opaque Apple IDs.
        let pattern = #"\b[A-Fa-f0-9]{16,}\b"#
        return replaceMatches(in: value, pattern: pattern) { match in
            guard match.count > 8 else { return match }
            return "\(match.prefix(8))…\(match.suffix(4))"
        }
    }

    private static func redactBase64Tokens(in value: String) -> String {
        // Require at least one Base64 punctuation character to avoid masking normal prose.
        let pattern = #"(?<![A-Za-z0-9])[A-Za-z0-9]{16,}[+/][A-Za-z0-9+/]{15,}={0,2}(?![A-Za-z0-9])"#
        return replaceMatches(in: value, pattern: pattern) { _ in "[redacted-base64]" }
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
