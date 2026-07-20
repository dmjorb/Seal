import Foundation

/// Central Bundle ID rules used by first signing, renewals, and Seal self-renewal.
///
/// Rules:
/// - First sign: default to `<original bundle id>.seal`.
/// - Renewal: keep the previously signed bundle id.
/// - Seal self-renewal: keep the currently running Seal bundle id.
/// - Advanced first sign: allow a validated custom bundle id.
enum BundleIDPolicy {
    static let sealSuffix = "seal"

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
        if app.isSeal {
            let identifier = currentSealBundleIdentifier
                ?? app.mappedBundleIdentifier
                ?? app.originalBundleIdentifier
            return try validated(identifier)
        }

        if app.state == .installed {
            let identifier = app.mappedBundleIdentifier
                ?? app.preferredBundleIdentifier
                ?? app.originalBundleIdentifier
            return try validated(identifier)
        }

        if let requested = normalized(requestedBundleIdentifier), requested.isEmpty == false {
            return try validated(requested)
        }

        if let preferred = normalized(app.preferredBundleIdentifier), preferred.isEmpty == false {
            return try validated(preferred)
        }

        return try validated(recommendedBundleIdentifier(for: app.originalBundleIdentifier))
    }

    static func recommendedBundleIdentifier(for original: String) -> String {
        let clean = normalized(original) ?? original
        if clean.lowercased().hasSuffix(".\(sealSuffix)") { return clean }
        return "\(clean).\(sealSuffix)"
    }

    static func isEditable(_ app: AppRecord) -> Bool {
        app.isSeal == false && app.state != .installed
    }

    static func displayMode(for app: AppRecord) -> String {
        if app.isSeal { return "Seal 自刷新已锁定" }
        if app.state == .installed { return "续签已锁定" }
        return "首次签名可修改"
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
            throw failure(reason: "Bundle ID 不能为空")
        }
        guard identifier.count <= 255 else {
            throw failure(reason: "Bundle ID 不能超过 255 个字符")
        }
        guard identifier.hasPrefix(".") == false,
              identifier.hasSuffix(".") == false,
              identifier.contains("..") == false else {
            throw failure(reason: "Bundle ID 不能以句点开头或结尾，也不能包含连续句点")
        }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")
        guard identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw failure(reason: "Bundle ID 只能包含字母、数字、连字符和句点")
        }

        let segments = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            throw failure(reason: "Bundle ID 建议使用反向域名格式，例如 com.example.app")
        }
        guard segments.allSatisfy({ segment in
            guard let first = segment.first, let last = segment.last else { return false }
            return first != "-" && last != "-"
        }) else {
            throw failure(reason: "Bundle ID 的每一段不能以连字符开头或结尾")
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
