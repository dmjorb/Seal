import Foundation
@preconcurrency import Minimuxer

actor MinimuxerInstallChannel: InstallChannel {
    private let pairingStore: PairingStore
    private let logDirectory: URL
    private let onDemandActivator: any VPNOnDemandActivating

    init(
        pairingStore: PairingStore,
        logDirectory: URL,
        onDemandActivator: any VPNOnDemandActivating = LocalDevVPNOnDemandActivator()
    ) {
        self.pairingStore = pairingStore
        self.logDirectory = logDirectory
        self.onDemandActivator = onDemandActivator
    }

    func start() async throws -> String {
        let diagnostics = await diagnose()
        if let failure = diagnostics.failure { throw failure }
        guard let deviceIdentifier = diagnostics.deviceIdentifier else {
            throw Self.channelNotReadyFailure
        }
        return deviceIdentifier
    }

    func diagnose() async -> InstallChannelDiagnostics {
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
            guard pairingRecord != nil else {
                return fail(.pairingFile, Self.missingPairingFailure)
            }
            pass(.pairingFile)

            #if targetEnvironment(simulator)
            deviceIdentifier = pairingRecord?.deviceIdentifier ?? "SIMULATOR"
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
            await waitForNetworkRefresh(rounds: 4, delay: .milliseconds(250))
            var tunnelReachable = await onDemandActivator.probeTunnel()
            if tunnelReachable == false {
                await onDemandActivator.activate()
                await waitForNetworkRefresh(rounds: 8, delay: .milliseconds(350))
                tunnelReachable = await onDemandActivator.probeTunnel()
            }
            if tunnelReachable { pass(.vpnTunnel) }

            if let udid = try await readyDeviceIdentifier() {
                pass(.vpnTunnel)
                deviceIdentifier = udid
                pass(.minimuxer)
                pass(.deviceIdentifier)
                if let mismatch = Self.pairingMismatchFailure(
                    expected: pairingRecord?.deviceIdentifier,
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
                try Minimuxer.start(pairingFile: pairing, logPath: logDirectory.path)
            } catch {
                return fail(.minimuxer, Self.connectionFailure(error))
            }
            await waitForNetworkRefresh(rounds: 40, delay: .milliseconds(500))
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
                expected: pairingRecord?.deviceIdentifier,
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
        return Minimuxer.ready()
        #endif
    }

    func install(ipaData: Data, bundleID: String) async throws {
        #if !targetEnvironment(simulator)
        guard await isReady() else { throw Self.channelNotReadyFailure }
        do {
            try Minimuxer.yeetAppAfc(bundleId: bundleID, ipaBytes: ipaData)
            try Minimuxer.installIpa(bundleId: bundleID)
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
            if Minimuxer.lookupApp(bundleId: bundleID) != nil { return }
            try? await Task.sleep(for: .milliseconds(650))
        }
        throw ImportFailure(
            title: "安装后验证失败",
            reason: "已发送安装请求，但设备端没有确认安装后的 Bundle ID。",
            recovery: "保持 LocalDevVPN 连接后重试；如应用已经出现在桌面，请重新检测安装通道。",
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
    ) async {
        for _ in 0..<rounds {
            NetworkObserver.shared.refreshEndpoint()
            try? await Task.sleep(for: delay)
        }
    }

    private func readyDeviceIdentifier() async throws -> String? {
        guard await isReady() else { return nil }
        guard let udid = Minimuxer.fetchUDID(), udid.isEmpty == false else {
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
            recovery: "保持 LocalDevVPN 已连接，重新检测；如持续失败，请导出日志",
            code: "SEAL-INSTALL-705"
        )
    }

    private static func installationFailure(_ error: Error) -> ImportFailure {
        ImportFailure(
            title: "无法安装已签名应用",
            reason: diagnostic(error),
            recovery: "保持 Wi-Fi 和 LocalDevVPN 连接后重试；如持续失败，请导出日志",
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
        reason: "检测 LocalDevVPN 前需要先导入当前设备的配对文件。",
        recovery: "导入配对文件",
        code: "SEAL-PAIR-203"
    )

    private static let vpnTunnelUnavailableFailure = ImportFailure(
        title: "VPN 通道不可达",
        reason: "系统 VPN 可能已显示连接，但 Seal 尚未连通 LocalDevVPN 的本机通道。请保持 VPN 开启，等待几秒后重新检测。",
        recovery: "重新检测",
        code: "SEAL-INSTALL-701"
    )

    private static let deviceNotRespondingFailure = ImportFailure(
        title: "设备未响应",
        reason: "LocalDevVPN 通道已打开，但 Seal 没有读取到设备 UDID。",
        recovery: "保持 VPN 已连接后重新检测",
        code: "SEAL-INSTALL-708"
    )

    private static let channelNotReadyFailure = ImportFailure(
        title: "安装通道未就绪",
        reason: "Seal 已尝试连接 LocalDevVPN，但未能读取到设备安装通道。请确认 iOS 设置里的 VPN 状态为已连接，并保持 LocalDevVPN 在后台可用。",
        recovery: "重新检测",
        code: "SEAL-INSTALL-706"
    )
}
