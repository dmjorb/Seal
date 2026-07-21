enum SigningStage: String, CaseIterable, Equatable, Sendable {
    case waitingForChannel
    case preparingAccount
    case preparingCertificate
    case preparingAppID
    case preparingProfiles
    case signing
    case installing
    case verifying

    var title: String {
        switch self {
        case .waitingForChannel, .preparingAccount:
            return "正在处理证书"
        case .preparingCertificate:
            return "正在处理证书"
        case .preparingAppID:
            return "正在创建 App ID"
        case .preparingProfiles:
            return "正在生成描述文件"
        case .signing:
            return "正在签名"
        case .installing:
            return "正在安装"
        case .verifying:
            return "正在安装"
        }
    }
}
