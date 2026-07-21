enum SigningStage: String, CaseIterable, Equatable, Sendable {
    case waitingForChannel
    case preparingAccount
    case preparingCertificate
    case preparingProfiles
    case signing
    case installing
    case verifying

    var title: String {
        switch self {
        case .preparingAccount:
            return "正在准备签名"
        case .preparingCertificate:
            return "正在处理 Bundle ID"
        case .preparingProfiles:
            return "正在生成描述文件"
        case .signing:
            return "正在写入签名"
        case .waitingForChannel:
            return "正在准备签名"
        case .installing:
            return "正在安装到设备"
        case .verifying:
            return "正在确认安装"
        }
    }
}
