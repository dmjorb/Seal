//
//  Muxer.swift
//  Minimuxer
//
//  Remote-pairing state management for Seal.
//

import Foundation
import RustBridge

public enum PairRecordAccessPolicy {
    public static func pairRecordData() -> Data? {
        nil
    }
}

public final class Muxer {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var started = false
        var remotePairing = false
        var deviceIP: String?
    }

    private static let state = State()

    public static var started: Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.started
    }

    public static var isrppairing: Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.remotePairing
    }

    /// The legacy localhost usbmuxd listener is intentionally unavailable.
    public static var usbmuxdReady: Bool { false }

    public static func retargetUsbmuxdAddr() {
        // The pure-Rust RSD transport connects through LocalDevVPN directly.
    }

    public static func start(pairingFile: String, logPath: String) throws {
        _ = logPath
        if started {
            return
        }

        guard let pairingData = pairingFile.data(using: .utf8),
              let dictionary = try? PropertyListSerialization.propertyList(
                  from: pairingData,
                  options: [],
                  format: nil
              ) as? [String: Any]
        else {
            throw MinimuxerError.PairingFile
        }

        guard hasRemotePrivateKey(dictionary) else {
            if dictionary["UDID"] != nil {
                throw MinimuxerError.LegacyPairingUnsupported
            }
            throw MinimuxerError.PairingFile
        }

        try RustIdevice.setRpPairingFile(pairingFile)

        state.lock.lock()
        state.remotePairing = true
        state.started = true
        state.lock.unlock()
    }

    public static func stop() {
        state.lock.lock()
        state.started = false
        state.remotePairing = false
        state.deviceIP = nil
        state.lock.unlock()
    }

    static var securityListenerActive: Bool { false }
    static var securityCachedPairingByteCount: Int { 0 }

    public static func notifyDeviceAttached(deviceIP: String) {
        state.lock.lock()
        state.deviceIP = deviceIP
        state.lock.unlock()
    }

    public static func notifyDeviceDetached() {
        state.lock.lock()
        state.deviceIP = nil
        state.lock.unlock()
    }

    private static func hasRemotePrivateKey(_ dictionary: [String: Any]) -> Bool {
        ["private_key", "privateKey", "PrivateKey"].contains { key in
            if let data = dictionary[key] as? Data {
                return data.isEmpty == false
            }
            if let string = dictionary[key] as? String {
                return string.isEmpty == false
            }
            return false
        }
    }
}
