import Foundation

struct SigningHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    enum Action: String, Codable, Sendable {
        case sign
        case renew
        case imported

        var displayTitle: String {
            switch self {
            case .sign: "首次签名"
            case .renew: "续签"
            case .imported: "历史回填"
            }
        }
    }

    enum Result: String, Codable, Sendable {
        case success
        case failed

        var displayTitle: String {
            switch self {
            case .success: "成功"
            case .failed: "失败"
            }
        }
    }

    enum LifecycleStatus: String, Codable, Sendable {
        case active
        case deleted
        case unknown

        var displayTitle: String {
            switch self {
            case .active: "当前有效"
            case .deleted: "已删除"
            case .unknown: "未确认"
            }
        }
    }

    let id: UUID
    let accountID: UUID
    let appID: UUID?
    let appName: String
    let originalBundleIdentifier: String
    let signedBundleIdentifier: String?
    var attemptedBundleIdentifier: String?
    var finalSignedBundleIdentifier: String?
    var lifecycleStatus: LifecycleStatus?
    let version: String
    let buildNumber: String
    let iconRelativePath: String?
    let accountDisplayName: String
    let teamID: String
    let teamName: String
    let certificateSerialNumber: String?
    let signedDeviceIdentifier: String?
    let provisioningProfileUUID: String?
    let provisioningProfileName: String?
    let provisioningProfileExpirationDate: Date?
    let entitlementValidationStatus: String?
    let capabilityValidationStatus: String?
    let extensionBundleIdentifiers: [String]?
    let removedExtensionBundleIdentifiers: [String]?
    let signingTargets: [SigningTargetRecord]?
    let action: Action
    let result: Result
    let signedAt: Date
    let expiryDate: Date?
    let errorCode: String?
    let errorReason: String?

    init(
        id: UUID = UUID(),
        accountID: UUID,
        appID: UUID?,
        appName: String,
        originalBundleIdentifier: String,
        signedBundleIdentifier: String?,
        attemptedBundleIdentifier: String? = nil,
        finalSignedBundleIdentifier: String? = nil,
        lifecycleStatus: LifecycleStatus? = nil,
        version: String,
        buildNumber: String,
        iconRelativePath: String?,
        accountDisplayName: String,
        teamID: String,
        teamName: String,
        certificateSerialNumber: String?,
        signedDeviceIdentifier: String? = nil,
        provisioningProfileUUID: String? = nil,
        provisioningProfileName: String? = nil,
        provisioningProfileExpirationDate: Date? = nil,
        entitlementValidationStatus: String? = nil,
        capabilityValidationStatus: String? = nil,
        extensionBundleIdentifiers: [String]? = nil,
        removedExtensionBundleIdentifiers: [String]? = nil,
        signingTargets: [SigningTargetRecord]? = nil,
        action: Action,
        result: Result,
        signedAt: Date = Date(),
        expiryDate: Date?,
        errorCode: String?,
        errorReason: String?
    ) {
        self.id = id
        self.accountID = accountID
        self.appID = appID
        self.appName = appName
        self.originalBundleIdentifier = originalBundleIdentifier
        self.signedBundleIdentifier = signedBundleIdentifier
        self.attemptedBundleIdentifier = attemptedBundleIdentifier
        self.finalSignedBundleIdentifier = finalSignedBundleIdentifier
        self.lifecycleStatus = lifecycleStatus
        self.version = version
        self.buildNumber = buildNumber
        self.iconRelativePath = iconRelativePath
        self.accountDisplayName = accountDisplayName
        self.teamID = teamID
        self.teamName = teamName
        self.certificateSerialNumber = certificateSerialNumber
        self.signedDeviceIdentifier = signedDeviceIdentifier
        self.provisioningProfileUUID = provisioningProfileUUID
        self.provisioningProfileName = provisioningProfileName
        self.provisioningProfileExpirationDate = provisioningProfileExpirationDate
        self.entitlementValidationStatus = entitlementValidationStatus
        self.capabilityValidationStatus = capabilityValidationStatus
        self.extensionBundleIdentifiers = extensionBundleIdentifiers
        self.removedExtensionBundleIdentifiers = removedExtensionBundleIdentifiers
        self.signingTargets = signingTargets
        self.action = action
        self.result = result
        self.signedAt = signedAt
        self.expiryDate = expiryDate
        self.errorCode = errorCode
        self.errorReason = errorReason
    }

    init(
        app: AppRecord,
        account: AppleAccountRecord,
        action: Action,
        result: Result,
        signedAt: Date = Date(),
        attemptedBundleIdentifier: String? = nil,
        finalSignedBundleIdentifier: String? = nil,
        lifecycleStatus: LifecycleStatus? = nil,
        errorCode: String? = nil,
        errorReason: String? = nil
    ) {
        self.init(
            accountID: account.id,
            appID: app.id,
            appName: app.name,
            originalBundleIdentifier: app.originalBundleIdentifier,
            signedBundleIdentifier: app.mappedBundleIdentifier,
            attemptedBundleIdentifier: attemptedBundleIdentifier ?? app.preferredBundleIdentifier,
            finalSignedBundleIdentifier: finalSignedBundleIdentifier ?? (result == .success ? app.mappedBundleIdentifier : nil),
            lifecycleStatus: lifecycleStatus ?? (app.state == .installed ? .active : .unknown),
            version: app.version,
            buildNumber: app.buildNumber,
            iconRelativePath: app.iconRelativePath,
            accountDisplayName: account.maskedEmail,
            teamID: account.teamID,
            teamName: account.teamName,
            certificateSerialNumber: app.certificateSerialNumber
                ?? account.selectedCertificateSerialNumber
                ?? account.certificateSerialNumber,
            signedDeviceIdentifier: app.signedDeviceIdentifier,
            provisioningProfileUUID: app.provisioningProfileUUID,
            provisioningProfileName: app.provisioningProfileName,
            provisioningProfileExpirationDate: app.provisioningProfileExpirationDate,
            entitlementValidationStatus: app.entitlementValidationStatus,
            capabilityValidationStatus: app.capabilityValidationStatus,
            extensionBundleIdentifiers: app.extensions.compactMap {
                $0.mappedBundleIdentifier ?? $0.originalBundleIdentifier
            },
            removedExtensionBundleIdentifiers: app.removedExtensionBundleIdentifiers,
            signingTargets: app.signingTargets,
            action: action,
            result: result,
            signedAt: signedAt,
            expiryDate: app.expiryDate,
            errorCode: errorCode,
            errorReason: errorReason
        )
    }

    var displayBundleIdentifier: String {
        if let finalSignedBundleIdentifier, finalSignedBundleIdentifier.isEmpty == false {
            return finalSignedBundleIdentifier
        }
        if let signedBundleIdentifier, signedBundleIdentifier.isEmpty == false {
            return signedBundleIdentifier
        }
        if let attemptedBundleIdentifier, attemptedBundleIdentifier.isEmpty == false {
            return attemptedBundleIdentifier
        }
        return originalBundleIdentifier
    }

    var attemptedDisplayBundleIdentifier: String {
        guard let attemptedBundleIdentifier,
              attemptedBundleIdentifier.isEmpty == false else {
            return displayBundleIdentifier
        }
        return attemptedBundleIdentifier
    }

    var versionDisplay: String {
        buildNumber.isEmpty ? "v\(version)" : "v\(version) (\(buildNumber))"
    }

    func statusText(now: Date = Date()) -> String {
        if result == .failed {
            return errorCode ?? "失败"
        }
        if lifecycleStatus == .deleted { return "已删除" }
        guard let expiryDate else { return "已签名" }
        let interval = expiryDate.timeIntervalSince(now)
        guard interval > 0 else { return "已过期" }
        let days = max(1, Int(ceil(interval / 86_400)))
        return "剩余 \(days) 天"
    }
}

struct SigningHistorySummary: Equatable, Sendable {
    let total: Int
    let succeeded: Int
    let failed: Int
    let valid: Int
    let expired: Int
    let latestSignedAt: Date?
    let deleted: Int

    static let empty = SigningHistorySummary(
        total: 0,
        succeeded: 0,
        failed: 0,
        valid: 0,
        expired: 0,
        latestSignedAt: nil,
        deleted: 0
    )

    init(records: [SigningHistoryRecord], now: Date = Date()) {
        total = records.count
        succeeded = records.filter { $0.result == .success }.count
        failed = records.filter { $0.result == .failed }.count
        valid = records.filter { record in
            record.result == .success
                && record.lifecycleStatus != .deleted
                && (record.expiryDate ?? .distantPast) > now
        }.count
        expired = records.filter { record in
            guard record.result == .success,
                  record.lifecycleStatus != .deleted,
                  let expiryDate = record.expiryDate else {
                return false
            }
            return expiryDate <= now
        }.count
        latestSignedAt = records.map(\.signedAt).max()
        deleted = records.filter { $0.lifecycleStatus == .deleted }.count
    }

    private init(
        total: Int,
        succeeded: Int,
        failed: Int,
        valid: Int,
        expired: Int,
        latestSignedAt: Date?,
        deleted: Int
    ) {
        self.total = total
        self.succeeded = succeeded
        self.failed = failed
        self.valid = valid
        self.expired = expired
        self.latestSignedAt = latestSignedAt
        self.deleted = deleted
    }
}
