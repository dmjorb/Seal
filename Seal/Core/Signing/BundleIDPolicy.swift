import Foundation

/// Bundle ID helpers. Seal validates only local string format; Apple/iOS decide availability.
enum BundleIDPolicy {
    static func canonicalSealBundleIdentifier(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "SealOriginalBundleIdentifier") as? String
            ?? "com.mjorb.seal"
    }

    static func currentSealBundleIdentifier(bundle: Bundle = .main) -> String? {
        bundle.bundleIdentifier
    }

    static func isLegacySelfBundleIdentifier(_ bundleIdentifier: String, bundle: Bundle = .main) -> Bool {
        let canonical = canonicalSealBundleIdentifier(bundle: bundle)
        return bundleIdentifier != canonical
            && bundleIdentifier.hasPrefix(canonical + ".")
    }

    static func targetBundleIdentifier(
        for app: AppRecord,
        requestedBundleIdentifier: String? = nil,
        currentSealBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> String {
        if let requested = normalized(requestedBundleIdentifier), requested.isEmpty == false {
            return try validated(requested)
        }
        if app.state == .installed {
            if let mapped = normalized(app.mappedBundleIdentifier), mapped.isEmpty == false {
                return try validated(mapped)
            }
            if let preferred = normalized(app.preferredBundleIdentifier), preferred.isEmpty == false {
                return try validated(preferred)
            }
            throw ImportFailure(
                title: "续签记录不完整",
                reason: "未记录当前已签名 Bundle ID。",
                recovery: "重新选择 IPA 签名并安装",
                code: "SEAL-BUNDLE-002"
            )
        }
        if let preferred = normalized(app.preferredBundleIdentifier), preferred.isEmpty == false {
            return try validated(preferred)
        }
        if let mapped = normalized(app.mappedBundleIdentifier), mapped.isEmpty == false {
            return try validated(mapped)
        }
        return try validated(app.originalBundleIdentifier)
    }

    static func recommendedBundleIdentifier(for original: String) -> String {
        normalized(original) ?? original
    }

    static func isEditable(_ app: AppRecord) -> Bool { true }

    static func displayMode(for app: AppRecord) -> String {
        "按 Apple / iOS 实际返回处理"
    }

    static func validationError(for value: String) -> String? {
        do {
            _ = try validated(value)
            return nil
        } catch let failure as ImportFailure {
            return failure.reason
        } catch {
            return "Bundle ID 格式无效"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validated(_ value: String) throws -> String {
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard identifier.isEmpty == false else {
            throw failure(reason: "不能为空")
        }
        guard identifier.count <= 255 else {
            throw failure(reason: "不能超过 255 个字符")
        }
        guard identifier.hasPrefix(".") == false,
              identifier.hasSuffix(".") == false,
              identifier.contains("..") == false else {
            throw failure(reason: "不能以 . 开头或结尾，不能包含连续 ..")
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")
        guard identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw failure(reason: "只能包含 A-Z、a-z、0-9、- 和 .")
        }
        let segments = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            throw failure(reason: "至少包含两段")
        }
        guard segments.allSatisfy({ segment in
            guard let first = segment.first, let last = segment.last else { return false }
            return first != "-" && last != "-"
        }) else {
            throw failure(reason: "每段不能以 - 开头或结尾")
        }
        return identifier
    }

    private static func failure(reason: String) -> ImportFailure {
        ImportFailure(
            title: "Bundle ID 无效",
            reason: reason,
            recovery: "修改 Bundle ID",
            code: "SEAL-BUNDLE-001"
        )
    }
}
