import Foundation

enum PairingValidationStatus: String, Codable, Equatable, Sendable {
    case unverified
    case validating
    case verified
    case deviceMismatch
    case fileUnreadable

    var title: String {
        switch self {
        case .unverified: return "已导入，待验证"
        case .validating: return "验证中"
        case .verified: return "已配对"
        case .deviceMismatch: return "配对设备不一致"
        case .fileUnreadable: return "文件无法读取"
        }
    }
}

struct PairingRecord: Equatable, Sendable {
    let deviceIdentifier: String?
    let isRemotePairing: Bool
    let validationStatus: PairingValidationStatus
    let validatedDeviceIdentifier: String?
    let validatedAt: Date?

    init(
        deviceIdentifier: String?,
        isRemotePairing: Bool,
        validationStatus: PairingValidationStatus = .unverified,
        validatedDeviceIdentifier: String? = nil,
        validatedAt: Date? = nil
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.isRemotePairing = isRemotePairing
        self.validationStatus = validationStatus
        self.validatedDeviceIdentifier = validatedDeviceIdentifier
        self.validatedAt = validatedAt
    }

    var effectiveDeviceIdentifier: String? {
        validatedDeviceIdentifier ?? deviceIdentifier
    }

    var isVerifiedForCurrentDevice: Bool {
        validationStatus == .verified && effectiveDeviceIdentifier?.isEmpty == false
    }
}
