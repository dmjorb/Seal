import Foundation

enum AppState: String, Codable, CaseIterable, Equatable, Sendable {
    case imported
    case preflightPassed
    case waitingForAccount
    case preparingCertificate
    case preparingProfiles
    case signing
    case signed
    case waitingForInstallChannel
    case installing
    case verifying
    case installed
    case failedRecoverable
    case failedFinal

    static let replaceablePendingImportStates: Set<AppState> = [
        .imported,
        .preflightPassed,
        .waitingForAccount,
        .failedRecoverable,
        .failedFinal
    ]

    var title: String {
        switch self {
        case .imported, .preflightPassed, .waitingForAccount:
            return "未签名"
        case .preparingCertificate, .preparingProfiles, .signing:
            return "签名中"
        case .signed:
            return "已签名"
        case .waitingForInstallChannel:
            return "等待连接"
        case .installing, .verifying:
            return "安装中"
        case .installed:
            return "已安装"
        case .failedRecoverable:
            return "可重试"
        case .failedFinal:
            return "失败"
        }
    }
}
