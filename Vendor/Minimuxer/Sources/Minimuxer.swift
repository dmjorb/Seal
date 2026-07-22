//
//  Minimuxer.swift
//  Minimuxer
//
//  Seal supports the modern remote-pairing transport only.
//

import Foundation
import RustBridge

public struct MinimuxerSecuritySnapshot: Equatable, Sendable {
    public let isListenerActive: Bool
    public let cachedPairingByteCount: Int
    public let rustHasPairingFile: Bool
    public let rustHasCachedConnection: Bool
    public let pairingGeneration: UInt64
}

public struct Minimuxer {
    public static func describeError(_ error: MinimuxerError) -> String {
        error.description
    }

    public static func bindTunnelConfig(_ binding: TunnelConfigBinding) {
        IfaceScanner.shared.bindTunnelConfig(binding)
    }

    public static func ready() -> Bool {
        guard Muxer.started, RustIdevice.hasRpPairingFile() else {
            return false
        }
        return RustIdevice.testDeviceConnection()
    }

    /// Kept for source compatibility. The pure-Rust transport uses Swift/Rust
    /// logging and has no libimobiledevice global debug level.
    public static func setDebug(_ debug: Bool) {
        _ = debug
    }

    public static func start(pairingFile: String, logPath: String) throws {
        try startWithLogger(
            pairingFile: pairingFile,
            logPath: logPath,
            isConsoleLoggingEnabled: true
        )
    }

    public static func startWithLogger(
        pairingFile: String,
        logPath: String,
        isConsoleLoggingEnabled: Bool
    ) throws {
        _ = logPath
        _ = isConsoleLoggingEnabled
        try Muxer.start(pairingFile: pairingFile, logPath: logPath)
    }

    public static func stop() {
        Muxer.stop()
        RustIdevice.clearRpPairingState()
    }

    public static func setRemotePairingFile(_ pairingFile: String) throws {
        try RustIdevice.setRpPairingFile(pairingFile)
    }

    public static func securitySnapshot() -> MinimuxerSecuritySnapshot {
        MinimuxerSecuritySnapshot(
            isListenerActive: Muxer.securityListenerActive,
            cachedPairingByteCount: Muxer.securityCachedPairingByteCount,
            rustHasPairingFile: RustIdevice.hasRpPairingFile(),
            rustHasCachedConnection: RustIdevice.hasCachedRsdConnection(),
            pairingGeneration: RustIdevice.rpPairingGeneration()
        )
    }

    public static func retargetUsbmuxdAddr() {
        // Remote pairing communicates directly with the LocalDevVPN endpoint.
    }

    public static func fetchUDID() -> String? {
        guard Muxer.started, RustIdevice.hasRpPairingFile() else {
            return nil
        }
        return RustIdevice.fetchUDID()
    }

    public static func testDeviceConnection(ifaddr: String?) -> Bool {
        guard ifaddr?.isEmpty == false else { return false }
        return RustIdevice.testDeviceConnection()
    }

    public static func yeetAppAfc(bundleId: String, ipaBytes: Data) throws {
        try Install.yeetAppAfc(bundleId: bundleId, ipaBytes: ipaBytes)
    }

    public static func installIpa(bundleId: String) throws {
        try Install.installIpa(bundleId: bundleId)
    }

    public static func removeApp(bundleId: String) throws {
        try Install.removeApp(bundleId: bundleId)
    }

    public static func lookupApp(bundleId: String) -> String? {
        guard Muxer.started else { return nil }
        guard (try? RustIdevice.lookupApp(bundleId: bundleId)) == true else {
            return nil
        }
        return bundleId
    }

    public static func debugApp(appId: String) throws {
        try JIT.debugApp(appId: appId)
    }

    public static func attachDebugger(pid: UInt32) throws {
        try JIT.attachDebugger(pid: pid)
    }

    public static func startAutoMounter(docsPath: String) {
        Mounter.startAutoMounter(docsPath: docsPath)
    }

    public static func installProvisioningProfile(profile: Data) throws {
        try Provision.installProvisioningProfile(profile: profile)
    }

    public static func removeProvisioningProfile(id: String) throws {
        try Provision.removeProvisioningProfile(id: id)
    }

    public static func dumpProfiles(docsPath: String) throws -> String {
        try Provision.dumpProfiles(docsPath: docsPath)
    }
}
