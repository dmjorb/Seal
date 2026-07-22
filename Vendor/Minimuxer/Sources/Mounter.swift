//
//  Mounter.swift
//  Minimuxer
//
//  Seal does not require personalized DDI mounting for its signing,
//  installation, or renewal closed loop.
//

import Foundation

public protocol MounterProvider: AnyObject, Sendable {
    var dmgMounted: Bool { get }
    func startAutoMounter(docsPath: String)
}

public enum Mounter {
    private static let provider = UnsupportedMounter()

    public static func startAutoMounter(docsPath: String) {
        provider.startAutoMounter(docsPath: docsPath)
    }

    public static var dmgMounted: Bool {
        provider.dmgMounted
    }
}

public final class UnsupportedMounter: MounterProvider, @unchecked Sendable {
    public init() {}

    public var dmgMounted: Bool { false }

    public func startAutoMounter(docsPath: String) {
        _ = docsPath
        print("[minimuxer] Personalized DDI mounting is unavailable in this Seal build")
    }
}
