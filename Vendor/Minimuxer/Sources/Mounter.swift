//
//  Mounter.swift
//  Minimuxer
//
//  Remote-pairing-only personalized DDI mounter.
//

import Foundation
import RustBridge

public protocol MounterProvider: AnyObject, Sendable {
    var dmgMounted: Bool { get }
    func startAutoMounter(docsPath: String)
}

public enum Mounter {
    private static let provider = RPMounter()

    public static func startAutoMounter(docsPath: String) {
        provider.startAutoMounter(docsPath: docsPath)
    }

    public static var dmgMounted: Bool {
        provider.dmgMounted
    }
}

public final class RPMounter: MounterProvider, @unchecked Sendable {
    private let stateLock = NSLock()
    private var mounted = false
    private var workerStarted = false

    public init() {}

    public var dmgMounted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return mounted
    }

    public func startAutoMounter(docsPath: String) {
        stateLock.lock()
        guard workerStarted == false else {
            stateLock.unlock()
            return
        }
        workerStarted = true
        stateLock.unlock()

        let rootPath = docsPath.hasPrefix("file://")
            ? String(docsPath.dropFirst(7))
            : docsPath
        let dmgDirectory = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("DMG", isDirectory: true)

        Thread.detachNewThread { [weak self] in
            self?.mountLoop(dmgDirectory: dmgDirectory)
        }
    }

    private func mountLoop(dmgDirectory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: dmgDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            print("[minimuxer] ERROR: Unable to create DDI directory: \(error)")
            markWorkerStopped()
            return
        }

        while dmgMounted == false {
            do {
                let image = try Self.loadPersonalizedImage(from: dmgDirectory)
                let result = RustIdevice.mountPersonalizedDDI(
                    image: image.image,
                    trustcache: image.trustcache,
                    manifest: image.manifest
                )
                if result == 0 {
                    markMounted()
                    print("[minimuxer] DDI mounted successfully")
                    return
                }
                print("[minimuxer] WARN: DDI mount returned code \(result); retrying")
            } catch {
                print("[minimuxer] WARN: DDI preparation failed: \(error); retrying")
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func markMounted() {
        stateLock.lock()
        mounted = true
        workerStarted = false
        stateLock.unlock()
    }

    private func markWorkerStopped() {
        stateLock.lock()
        workerStarted = false
        stateLock.unlock()
    }

    private static func loadPersonalizedImage(
        from directory: URL
    ) throws -> (image: Data, trustcache: Data, manifest: Data) {
        let resources: [(remote: String, local: URL)] = [
            (
                MuxerConstants.ddiImageURL,
                directory.appendingPathComponent("Image.dmg")
            ),
            (
                MuxerConstants.ddiTrustcacheURL,
                directory.appendingPathComponent("Image.dmg.trustcache")
            ),
            (
                MuxerConstants.ddiManifestURL,
                directory.appendingPathComponent("BuildManifest.plist")
            )
        ]

        for resource in resources where FileManager.default.fileExists(atPath: resource.local.path) == false {
            guard let remoteURL = URL(string: resource.remote) else {
                throw MinimuxerError.DownloadImage
            }
            let data = try Data(contentsOf: remoteURL)
            try data.write(to: resource.local, options: .atomic)
        }

        return (
            try Data(contentsOf: resources[0].local),
            try Data(contentsOf: resources[1].local),
            try Data(contentsOf: resources[2].local)
        )
    }
}
