//
//  Provision.swift
//  Minimuxer
//
//  Remote-pairing-only provisioning facade.
//

import Foundation
import RustBridge

public protocol ProvisionProvider: Sendable {
    func installProvisioningProfile(profile: Data) throws
    func removeProvisioningProfile(id: String) throws
    func dumpProfiles(docsPath: String) throws -> String
}

public enum Provision {
    private static let provider = RPProvision()

    public static func installProvisioningProfile(profile: Data) throws {
        try provider.installProvisioningProfile(profile: profile)
    }

    public static func removeProvisioningProfile(id: String) throws {
        try provider.removeProvisioningProfile(id: id)
    }

    public static func dumpProfiles(docsPath: String) throws -> String {
        try provider.dumpProfiles(docsPath: docsPath)
    }
}

public struct RPProvision: ProvisionProvider {
    public init() {}

    public func dumpProfiles(docsPath: String) throws -> String {
        let path = docsPath.hasPrefix("file://") ? String(docsPath.dropFirst(7)) : docsPath
        try RustIdevice.dumpProfiles(path)
        return "\(path)/PROVISION"
    }

    public func installProvisioningProfile(profile: Data) throws {
        try RustIdevice.installProvisioningProfile(profile)
    }

    public func removeProvisioningProfile(id: String) throws {
        try RustIdevice.removeProvisioningProfile(id: id)
    }
}
