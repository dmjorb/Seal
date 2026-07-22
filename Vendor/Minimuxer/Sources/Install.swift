//
//  Install.swift
//  Minimuxer
//
//  Remote-pairing-only installation facade.
//

import Foundation
import RustBridge

public protocol InstallProvider: Sendable {
    func yeetAppAfc(bundleId: String, ipaBytes: Data) throws
    func installIpa(bundleId: String) throws
    func removeApp(bundleId: String) throws
}

public enum Install {
    private static let provider = RPInstall()

    public static func yeetAppAfc(bundleId: String, ipaBytes: Data) throws {
        try provider.yeetAppAfc(bundleId: bundleId, ipaBytes: ipaBytes)
    }

    public static func installIpa(bundleId: String) throws {
        try provider.installIpa(bundleId: bundleId)
    }

    public static func removeApp(bundleId: String) throws {
        try provider.removeApp(bundleId: bundleId)
    }
}

public struct RPInstall: InstallProvider {
    public init() {}

    public func yeetAppAfc(bundleId: String, ipaBytes: Data) throws {
        try RustIdevice.yeetAppAfc(bundleId: bundleId, ipaBytes: ipaBytes)
    }

    public func installIpa(bundleId: String) throws {
        try RustIdevice.installIpa(bundleId: bundleId)
    }

    public func removeApp(bundleId: String) throws {
        try RustIdevice.removeApp(bundleId: bundleId)
    }
}
