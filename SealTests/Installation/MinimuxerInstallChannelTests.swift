import Foundation
import Testing
@testable import Seal

struct MinimuxerInstallChannelTests {
    @Test
    func legacyPairingIsRejectedBeforeTheRuntimeCanCacheOrListen() async throws {
        let fixture = try await makePairingStore(
            dictionary: [
                "UDID": "legacy-device",
                "HostID": "host",
                "SystemBUID": "buid",
                "HostCertificate": Data([1]),
                "HostPrivateKey": Data([2]),
                "RootCertificate": Data([3]),
                "RootPrivateKey": Data([4])
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InstallRuntimeSpy()
        let channel = MinimuxerInstallChannel(
            pairingStore: fixture.store,
            logDirectory: fixture.root.appending(path: "Logs"),
            onDemandActivator: AlwaysReachableVPN(),
            runtime: runtime
        )

        do {
            _ = try await channel.start()
            Issue.record("Expected legacy pairing to be rejected")
        } catch let failure as ImportFailure {
            #expect(failure.code == "SEAL-PAIR-301")
        }

        #expect(await runtime.startCallCount == 0)
        #expect(await runtime.isListening == false)
        #expect(await runtime.hasCachedPairingData == false)
    }

    @Test
    func remotePairingPrivateKeyRemainsAnAcceptedChannelInput() async throws {
        let fixture = try await makePairingStore(
            dictionary: ["private_key": Data([1, 2, 3])]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InstallRuntimeSpy()
        let channel = MinimuxerInstallChannel(
            pairingStore: fixture.store,
            logDirectory: fixture.root.appending(path: "Logs"),
            onDemandActivator: AlwaysReachableVPN(),
            runtime: runtime
        )

        let identifier = try await channel.start()

        #expect(identifier.isEmpty == false)
        await channel.stop()
    }

    @Test
    func startedChannelStopsAfterSuccessFailureAndCancellation() async {
        for outcome in ChannelOutcome.allCases {
            let channel = LifecycleInstallChannel(outcome: outcome)
            do {
                _ = try await channel.withStartedChannel { _ in
                    switch outcome {
                    case .success: return "installed"
                    case .failure: throw ChannelTestError.expected
                    case .cancellation: throw CancellationError()
                    }
                }
            } catch {
                switch outcome {
                case .success:
                    Issue.record("Unexpected success-path error: \(error)")
                case .failure:
                    #expect(error is ChannelTestError)
                case .cancellation:
                    #expect(error is CancellationError)
                }
            }
            #expect(await channel.stopCallCount == 1)
            #expect(await channel.containsSensitiveData == false)
        }
    }

    private func makePairingStore(
        dictionary: [String: Any]
    ) async throws -> (root: URL, store: PairingStore) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "MinimuxerChannelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Pairing.plist")
        let stored = root.appending(path: "Stored.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        try data.write(to: source)
        let store = PairingStore(fileURL: stored)
        _ = try await store.importFile(at: source)
        return (root, store)
    }
}

private struct AlwaysReachableVPN: VPNOnDemandActivating {
    func activate() async {}
    func probeTunnel() async -> Bool { true }
}

private actor InstallRuntimeSpy: MinimuxerRuntime {
    private(set) var startCallCount = 0
    private(set) var isListening = false
    private(set) var hasCachedPairingData = false

    func start(pairingFile: String, logPath: String) async {
        startCallCount += 1
        hasCachedPairingData = true
    }

    func stop() async {
        isListening = false
        hasCachedPairingData = false
    }

    func isReady() async -> Bool { true }
    func fetchDeviceIdentifier() async -> String? { "remote-device" }
    func stageIPA(bundleID: String, data: Data) async {}
    func installIPA(bundleID: String) async {}
    func lookupApp(bundleID: String) async -> String? { bundleID }
}

private enum ChannelOutcome: CaseIterable {
    case success
    case failure
    case cancellation
}

private enum ChannelTestError: Error {
    case expected
}

private actor LifecycleInstallChannel: InstallChannel {
    let outcome: ChannelOutcome
    private(set) var stopCallCount = 0
    private(set) var containsSensitiveData = false

    init(outcome: ChannelOutcome) {
        self.outcome = outcome
    }

    func start() async -> String {
        containsSensitiveData = true
        return "device"
    }

    func stop() async {
        stopCallCount += 1
        containsSensitiveData = false
    }

    func diagnose() async -> InstallChannelDiagnostics { .empty }
    func isReady() async -> Bool { true }
    func install(ipaData: Data, bundleID: String, isSelfReplacement: Bool) async {}
    func verifyInstalled(bundleID: String) async {}
}
