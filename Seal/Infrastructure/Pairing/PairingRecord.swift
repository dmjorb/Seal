import Foundation

enum PairingValidationStatus: String, Codable, Equatable, Sendable {
    case unverified
    case verified
    case deviceMismatch
    case connectionFailed

    var title: String {
        switch self {
        case .unverified: return "已导入，待验证"
        case .verified: return "已配对"
        case .deviceMismatch: return "不属于当前设备"
        case .connectionFailed: return "连接验证失败"
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
