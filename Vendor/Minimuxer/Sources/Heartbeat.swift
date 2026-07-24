//
//  Heartbeat.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge

public class Heartbeat {
    private static let stateLock = NSLock()
    private static var _lastBeatSuccessful = false

    public static var lastBeatSuccessful: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastBeatSuccessful
    }

    public static func reset() {
        setLastBeatSuccessful(false)
    }

    public static func startBeat(generation: UInt64) {
        Thread.detachNewThread {
            print("[minimuxer] Starting heartbeat thread...")
            while Muxer.isCurrentGeneration(generation), Muxer.usbmuxdReady == false {
                Thread.sleep(forTimeInterval: 1)
                let timestamp = ISO8601DateFormatter().string(from: Date())
                print("[\(timestamp)] [minimuxer] heartbeat-thread: Waiting for usbmuxd to be ready...")
            }
            guard Muxer.isCurrentGeneration(generation) else { return }
            print("[minimuxer] heartbeat-thread: usbmuxd is ready")

            while Muxer.isCurrentGeneration(generation) {
                let deviceIP: String
                do {
                    deviceIP = try DeviceEndpoint.shared.ip()
                } catch {
                    print("[minimuxer] heartbeat-thread: deviceIP unavailable")
                    setLastBeatSuccessful(false, generation: generation)
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                if Minimuxer.testDeviceConnection(ifaddr: deviceIP) == false {
                    print("[minimuxer] heartbeat-thread: device IP not reachable, waiting...")
                    setLastBeatSuccessful(false, generation: generation)
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }
                print("[minimuxer] heartbeat-thread: device IP reachable at: \(deviceIP)")

                let device: Device
                do {
                    device = try Device.getFirstDevice()
                } catch {
                    print("[minimuxer] WARN: Could not query device from usbmuxd for heartbeat")
                    setLastBeatSuccessful(false, generation: generation)
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                guard let heartbeat = RustHeartbeat.connect(
                    device: device.internalInstance,
                    label: "minimuxer"
                ) else {
                    print("[minimuxer] ERROR: Failed to create heartbeat client")
                    setLastBeatSuccessful(false, generation: generation)
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                while Muxer.isCurrentGeneration(generation) {
                    guard let plist = heartbeat.receive(
                        timeoutMs: MuxerConstants.heartbeatTimeoutMs
                    ) else {
                        print("[minimuxer] ERROR: Heartbeat recv failed")
                        setLastBeatSuccessful(false, generation: generation)
                        break
                    }

                    if heartbeat.send(plistXml: plist) {
                        setLastBeatSuccessful(true, generation: generation)
                    } else {
                        print("[minimuxer] ERROR: Heartbeat send failed")
                        setLastBeatSuccessful(false, generation: generation)
                        break
                    }
                }
            }
        }
    }

    private static func setLastBeatSuccessful(
        _ value: Bool,
        generation: UInt64? = nil
    ) {
        if let generation, Muxer.isCurrentGeneration(generation) == false { return }
        stateLock.lock()
        _lastBeatSuccessful = value
        stateLock.unlock()
    }
}
