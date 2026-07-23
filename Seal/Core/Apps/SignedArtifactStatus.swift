import Foundation

enum SignedArtifactStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case available
    case awaitingVerification
    case installed
    case installFailed
    case expired
    case deviceUnavailable
    case damaged
    case missing

    var title: String {
        switch self {
        case .available: "未安装"
        case .awaitingVerification: "待验证"
        case .installed: "已安装"
        case .installFailed: "安装失败"
        case .expired: "已过期"
        case .deviceUnavailable: "当前设备不可用"
        case .damaged: "文件损坏"
        case .missing: "文件缺失"
        }
    }
}
