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
            return "验证账号"
        case .preparingCertificate:
            return "准备证书"
        case .preparingProfiles:
            return "准备描述文件"
        case .signing:
            return "签名"
        case .waitingForChannel:
            return "连接设备"
        case .installing:
            return "安装"
        case .verifying:
            return "完成验证"
        }
    }
}
