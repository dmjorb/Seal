import Foundation

@MainActor
final class OperationCoordinator {
    enum Kind: String, Equatable, Sendable {
        case importing
        case signing
        case installing
        case renewing
        case managingCertificate
        case managingAccount
        case maintainingStorage
        case resettingPairing

        var title: String {
            switch self {
            case .importing: return "正在导入"
            case .signing: return "正在签名"
            case .installing: return "正在安装"
            case .renewing: return "正在续签"
            case .managingCertificate: return "正在管理证书"
            case .managingAccount: return "正在管理 Apple ID"
            case .maintainingStorage: return "正在维护存储"
            case .resettingPairing: return "正在更新配对"
            }
        }
    }

    struct Lease: Equatable, Sendable {
        fileprivate let id: UUID
        let kind: Kind
        let appID: UUID?

        static func uncoordinated(_ kind: Kind, appID: UUID?) -> Lease {
            Lease(id: UUID(), kind: kind, appID: appID)
        }
    }

    private(set) var activeLease: Lease?

    func begin(_ kind: Kind, appID: UUID? = nil) -> Lease? {
        guard activeLease == nil else { return nil }
        let lease = Lease(id: UUID(), kind: kind, appID: appID)
        activeLease = lease
        return lease
    }

    func end(_ lease: Lease) {
        guard activeLease?.id == lease.id else { return }
        activeLease = nil
    }

    func conflictFailure(requested: Kind) -> ImportFailure {
        let activeTitle = activeLease?.kind.title ?? "其他操作"
        return ImportFailure(
            title: "暂时无法执行",
            reason: "\(activeTitle)，为避免签名、证书或文件状态互相覆盖，当前操作已阻止。",
            recovery: "等待当前操作完成后重试",
            code: "SEAL-OP-001"
        )
    }
}
