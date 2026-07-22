//
//  Jit.swift
//  Minimuxer
//
//  Remote-pairing-only JIT facade.
//

import Foundation
import RustBridge

public protocol JITProvider: Sendable {
    func debugApp(appId: String) throws
    func attachDebugger(pid: UInt32) throws
}

public enum JIT {
    private static let provider = RPJit()

    public static func debugApp(appId: String) throws {
        try provider.debugApp(appId: appId)
    }

    public static func attachDebugger(pid: UInt32) throws {
        try provider.attachDebugger(pid: pid)
    }
}

public struct RPJit: JITProvider {
    public init() {}

    public func debugApp(appId: String) throws {
        try RustIdevice.debugApp(appId: appId)
    }

    public func attachDebugger(pid: UInt32) throws {
        try RustIdevice.debugApp(pid: pid)
    }
}
