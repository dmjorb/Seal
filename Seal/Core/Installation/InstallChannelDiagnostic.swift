import Foundation

enum InstallDiagnosticStepKind: String, Codable, Sendable {
    case pairingFile
    case vpnTunnel
    case minimuxer
    case deviceIdentifier
    case pairingMatch
    case installationService
}

struct InstallDiagnosticStep: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case pending
        case running
        case passed
        case failed(ImportFailure)
    }

    let kind: InstallDiagnosticStepKind
    var status: Status

    var title: String {
        switch kind {
        case .pairingFile: "配对文件"
        case .vpnTunnel: "VPN 通道"
        case .minimuxer: "安装通道"
        case .deviceIdentifier: "设备响应"
        case .pairingMatch: "配对匹配"
        case .installationService: "安装服务"
        }
    }

    var valueText: String {
        switch status {
        case .pending: "待检测"
        case .running: "检测中"
        case .passed: "正常"
        case .failed(let failure): failure.title
        }
    }
}

struct InstallChannelDiagnostics: Equatable, Sendable {
    var steps: [InstallDiagnosticStep]
    var deviceIdentifier: String?
    var failure: ImportFailure?

    var isReady: Bool {
        failure == nil && steps.allSatisfy { step in
            if case .passed = step.status { return true }
            return false
        }
    }

    static var empty: InstallChannelDiagnostics {
        InstallChannelDiagnostics(
            steps: InstallDiagnosticStepKind.allCasesForDisplay.map {
                InstallDiagnosticStep(kind: $0, status: .pending)
            },
            deviceIdentifier: nil,
            failure: nil
        )
    }
}

extension InstallDiagnosticStepKind {
    static let allCasesForDisplay: [InstallDiagnosticStepKind] = [
        .pairingFile,
        .vpnTunnel,
        .minimuxer,
        .deviceIdentifier,
        .pairingMatch,
        .installationService
    ]
}
