import Foundation
import UIKit
@preconcurrency import Minimuxer

protocol MinimuxerRuntime: Sendable {
    func start(pairingFile: String, logPath: String) async throws
    func stop() async
    func isReady() async -> Bool
    func fetchDeviceIdentifier() async -> String?
    func stageIPA(bundleID: String, data: Data) async throws
    func installIPA(bundleID: String) async throws
    func lookupApp(bundleID: String) async -> String?
}

struct LiveMinimuxerRuntime: MinimuxerRuntime {
    func start(pairingFile: String, logPath: String) async throws {
        try Minimuxer.start(pairingFile: pairingFile, logPath: logPath)
    }

    func stop() async {
        Minimuxer.stop()
    }

    func isReady() async -> Bool {
        Minimuxer.ready()
    }

    func fetchDeviceIdentifier() async -> String? {
        Minimuxer.fetchUDID()
    }

    func stageIPA(bundleID: String, data: Data) async throws {
        try Minimuxer.yeetAppAfc(bundleId: bundleID, ipaBytes: data)
    }

    func installIPA(bundleID: String) async throws {
        try Minimuxer.installIpa(bundleId: bundleID)
    }

    func lookupApp(bundleID: String) async -> String? {
        Minimuxer.lookupApp(bundleId: bundleID)
    }
}

actor MinimuxerInstallChannel: InstallChannel {
    private let pairingStore: PairingStore
    private let logDirectory: URL
    private let onDemandActivator: any VPNOnDemandActivating
    private let runtime: any MinimuxerRuntime

    init(
        pairingStore: PairingStore,
        logDirectory: URL,
        onDemandActivator: any VPNOnDemandActivating = LocalDevVPNOnDemandActivator(),
        runtime: any MinimuxerRuntime = LiveMinimuxerRuntime()
    ) {
        self.pairingStore = pairingStore
        self.logDirectory = logDirectory
        self.onDemandActivator = onDemandActivator
        self.runtime = runtime
    }

    func start() async throws -> String {
        do {
            let diagnostics = try await diagnoseForStart()
            if let failure = diagnostics.failure { throw failure }
            guard let deviceIdentifier = diagnostics.deviceIdentifier else {
                throw Self.channelNotReadyFailure
            }
            return deviceIdentifier
        } catch is CancellationError {
            await stop()
            throw CancellationError()
        } catch {
            await stop()
            throw error
        }
    }

    func diagnose() async -> InstallChannelDiagnostics {
        do {
            let diagnostics = try await diagnoseForStart()
            await stop()
            return diagnostics
        } catch {
            await stop()
            return InstallChannelDiagnostics(
                steps: InstallChannelDiagnostics.empty.steps,
                deviceIdentifier: nil,
                failure: Self.channelNotReadyFailure
            )
        }
    }

    func stop() async {
        await runtime.stop()
        #if !targetEnvironment(simulator)
        _ = NetworkObserver.shared.stop()
        #endif
    }

    private func diagnoseForStart() async throws -> InstallChannelDiagnostics {
        var steps = InstallChannelDiagnostics.empty.steps
        var deviceIdentifier: String?

        func pass(_ kind: InstallDiagnosticStepKind) {
            if let index = steps.firstIndex(where: { $0.kind == kind }) {
                steps[index].status = .passed
            }
        }

        func fail(
            _ kind: InstallDiagnosticStepKind,
            _ failure: ImportFailure
        ) -> InstallChannelDiagnostics {
            if let index = steps.firstIndex(where: { $0.kind == kind }) {
                steps[index].status = .failed(failure)
            }
            return InstallChannelDiagnostics(
                steps: steps,
                deviceIdentifier: deviceIdentifier,
                failure: failure
            )
        }

        func run(_ kind: InstallDiagnosticStepKind) {
            if let index = steps.firstIndex(where: { $0.kind == kind }) {
                steps[index].status = .running
            }
        }

        do {
            run(.pairingFile)
            let pairingRecord = try await pairingStore.current()
            _ = try await pairingStore.contents()
            guard let pairingRecord else {
                return fail(.pairingFile, Self.missingPairingFailure)
            }
            guard pairingRecord.isRemotePairing else {
                return fail(.pairingFile, Self.legacyPairingUnsupportedFailure)
            }
            pass(.pairingFile)

            #if targetEnvironment(simulator)
            deviceIdentifier = pairingRecord.deviceIdentifier ?? "SIMULATOR"
            pass(.vpnTunnel)
            pass(.minimuxer)
            pass(.deviceIdentifier)
            pass(.pairingMatch)
            pass(.installationService)
            return InstallChannelDiagnostics(
                steps: steps,
                deviceIdentifier: deviceIdentifier,
                failure: nil
            )
            #else
            try FileManager.default.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true
            )
            NetworkObserver.shared.start()
            bindTunnelConfiguration()

            run(.vpnTunnel)
            try await waitForNetworkRefresh(rounds: 4, delay: .milliseconds(250))
            let tunnelReachable = await onDemandActivator.probeTunnel()
            if tunnelReachable { pass(.vpnTunnel) }

            if let udid = try await readyDeviceIdentifier() {
                pass(.vpnTunnel)
                deviceIdentifier = udid
                pass(.minimuxer)
                pass(.deviceIdentifier)
                if let mismatch = Self.pairingMismatchFailure(
                    expected: pairingRecord.deviceIdentifier,
                    actual: udid
                ) {
                    return fail(.pairingMatch, mismatch)
                }
                pass(.pairingMatch)
                pass(.installationService)
                return InstallChannelDiagnostics(
                    steps: steps,
                    deviceIdentifier: deviceIdentifier,
                    failure: nil
                )
            }

            run(.minimuxer)
            do {
                let pairing = try await pairingStore.contents()
                try await runtime.start(pairingFile: pairing, logPath: logDirectory.path)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return fail(.minimuxer, Self.connectionFailure(error))
            }
            try await waitForNetworkRefresh(rounds: 40, delay: .milliseconds(500))
            guard let udid = try await readyDeviceIdentifier() else {
                if tunnelReachable == false {
                    return fail(.vpnTunnel, Self.vpnTunnelUnavailableFailure)
                }
                return fail(.deviceIdentifier, Self.deviceNotRespondingFailure)
            }
            pass(.vpnTunnel)
            deviceIdentifier = udid
            pass(.minimuxer)
            pass(.deviceIdentifier)

            if let mismatch = Self.pairingMismatchFailure(
                expected: pairingRecord.deviceIdentifier,
                actual: udid
            ) {
                return fail(.pairingMatch, mismatch)
            }
            pass(.pairingMatch)

            guard await isReady() else {
                return fail(.installationService, Self.channelNotReadyFailure)
            }
            pass(.installationService)
            return InstallChannelDiagnostics(
                steps: steps,
                deviceIdentifier: udid,
                failure: nil
            )
            #endif
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ImportFailure {
            return fail(.pairingFile, failure)
        } catch {
            return fail(.pairingFile, Self.missingPairingFailure)
        }
    }

    func isReady() async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return await runtime.isReady()
        #endif
    }

    func install(
        ipaData: Data,
        bundleID: String,
        isSelfReplacement: Bool
    ) async throws {
        #if !targetEnvironment(simulator)
        try Task.checkCancellation()
        guard await isReady() else { throw Self.channelNotReadyFailure }
        do {
            try Task.checkCancellation()
            try await runtime.stageIPA(bundleID: bundleID, data: ipaData)
            try Task.checkCancellation()

            let backgroundTask: UIBackgroundTaskIdentifier? = if isSelfReplacement {
                await SelfReplacementController.beginInstallationBackgroundTask()
            } else {
                nil
            }
            if isSelfReplacement {
                await SelfReplacementController.returnToHomeScreen()
            }

            do {
                try Task.checkCancellation()
                try await runtime.installIPA(bundleID: bundleID)
                try Task.checkCancellation()
                if let backgroundTask {
                    await SelfReplacementController.endInstallationBackgroundTask(backgroundTask)
                }
            } catch {
                if let backgroundTask {
                    await SelfReplacementController.endInstallationBackgroundTask(backgroundTask)
                }
                throw error
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.installationFailure(error)
        }
        #endif
    }

    func verifyInstalled(bundleID: String) async throws {
        #if targetEnvironment(simulator)
        return
        #else
        guard await isReady() else { throw Self.channelNotReadyFailure }
        for _ in 0..<8 {
            try Task.checkCancellation()
            if await runtime.lookupApp(bundleID: bundleID) != nil { return }
            try await Task.sleep(for: .milliseconds(650))
        }
        throw ImportFailure(
            title: "安装后验证失败",
            reason: "iOS 安装服务未返回已安装的 Bundle ID。",
            recovery: "重试",
            code: "SEAL-INSTALL-707"
        )
        #endif
    }

    #if !targetEnvironment(simulator)
    private func bindTunnelConfiguration() {
        Minimuxer.bindTunnelConfig(
            TunnelConfigBinding(
                setDeviceIP: { _ in },
                setFakeIP: { _ in },
                setSubnetMask: { _ in },
                getOverrideFakeIP: { "10.7.0.1" },
                setOverrideEffective: { _ in }
            )
        )
    }

    private func waitForNetworkRefresh(
        rounds: Int,
        delay: Duration
    ) async throws {
        for _ in 0..<rounds {
            try Task.checkCancellation()
            NetworkObserver.shared.refreshEndpoint()
            try await Task.sleep(for: delay)
        }
    }

    private func readyDeviceIdentifier() async throws -> String? {
        guard await isReady() else { return nil }
        guard let udid = await runtime.fetchDeviceIdentifier(), udid.isEmpty == false else {
            return nil
        }
        return udid
    }

    private static func connectionFailure(_ error: Error) -> ImportFailure {
        let message = diagnostic(error)
        let normalized = message.lowercased()
        if normalized.contains("pair")
            || normalized.contains("pairing")
            || normalized.contains("lockdown")
            || normalized.contains("hostid")
            || normalized.contains("invalid host") {
            return ImportFailure(
                title: "设备配对不可用",
                reason: message,
                recovery: "重新导入当前设备的配对文件",
                code: "SEAL-INSTALL-703"
            )
        }
        if normalized.contains("trust") || normalized.contains("trusted") {
            return ImportFailure(
                title: "设备尚未信任",
                reason: message,
                recovery: "在 iPhone 上信任此设备后重试",
                code: "SEAL-INSTALL-704"
            )
        }
        if normalized.contains("timeout")
            || normalized.contains("timed out")
            || normalized.contains("connection")
            || normalized.contains("network")
            || normalized.contains("refused")
            || normalized.contains("unreachable")
            || normalized.contains("no connection")
            || normalized.contains("nodevice")
            || normalized.contains("no device") {
            return channelNotReadyFailure
        }
        return ImportFailure(
            title: "安装通道不可用",
            reason: message,
            recovery: "重试",
            code: "SEAL-INSTALL-705"
        )
    }

    private static func installationFailure(_ error: Error) -> ImportFailure {
        ImportFailure(
            title: "无法安装已签名应用",
            reason: diagnostic(error),
            recovery: "重试",
            code: "SEAL-INSTALL-702"
        )
    }

    private static func diagnostic(_ error: Error) -> String {
        let nsError = error as NSError
        if let minimuxerError = error as? MinimuxerError {
            return Minimuxer.describeError(minimuxerError)
        }
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }
    #endif

    private static func pairingMismatchFailure(
        expected: String?,
        actual: String
    ) -> ImportFailure? {
        guard let expected,
              expected.isEmpty == false,
              expected.caseInsensitiveCompare(actual) != .orderedSame else {
            return nil
        }
        return ImportFailure(
            title: "配对文件不匹配",
            reason: "当前配对文件属于另一台设备，无法用于这台 iPhone。",
            recovery: "重新导入当前设备的配对文件",
            code: "SEAL-PAIR-205"
        )
    }

    private static let missingPairingFailure = ImportFailure(
        title: "缺少配对文件",
        reason: "当前设备没有可用配对文件。",
        recovery: "导入配对文件",
        code: "SEAL-PAIR-203"
    )

    private static let legacyPairingUnsupportedFailure = ImportFailure(
        title: "需要重新配对",
        reason: "旧式 lockdown 配对文件需要向本机端口公开私钥，Seal 已停用这条不安全路径。",
        recovery: "请重新生成并导入 RPPairing 私钥配对文件。",
        code: "SEAL-PAIR-301"
    )

    private static let vpnTunnelUnavailableFailure = ImportFailure(
        title: "安装通道不可用",
        reason: "系统 VPN 已连接，但本机安装通道不可达。",
        recovery: "重试",
        code: "SEAL-INSTALL-701"
    )

    private static let deviceNotRespondingFailure = ImportFailure(
        title: "设备未响应",
        reason: "安装通道已打开，但未读取到设备 UDID。",
        recovery: "重试",
        code: "SEAL-INSTALL-708"
    )

    private static let channelNotReadyFailure = ImportFailure(
        title: "安装通道未就绪",
        reason: "未读取到可用的设备安装通道。",
        recovery: "重试",
        code: "SEAL-INSTALL-706"
    )
}
