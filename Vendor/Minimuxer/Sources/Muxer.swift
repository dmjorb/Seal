//
//  Muxer.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public class Muxer {
    private static let stateLock = NSLock()
    private static var _started = false
    private static var _usbmuxdReady = false
    private static var _isrppairing = false
    private static var generation: UInt64 = 0
    private static var listenerFD: Int32?

    public static var started: Bool { stateSnapshot().started }
    public static var usbmuxdReady: Bool { stateSnapshot().ready }
    public static var isrppairing: Bool { stateSnapshot().remotePairing }

    private static let DEVICE_ATTACH = "Attached"
    private static let DEVICE_DETACH = "Detached"

    private static var cachedPairingDict: [String: Any]?
    private static var cachedPairingXml: Data?

    // Stable device state
    private static var currentDeviceIP: String?
    private static var currentEvent: String?

    public static func retargetUsbmuxdAddr() {
        print("[minimuxer] unsetenv(USBMUXD_SOCKET_ADDRESS)")
        unsetenv(MuxerConstants.usbmuxdEnvKey)
        print("[minimuxer] setenv(USBMUXD_SOCKET_ADDRESS, \(MuxerConstants.usbmuxdSocket))")
        setenv(MuxerConstants.usbmuxdEnvKey, MuxerConstants.usbmuxdSocket, 1)
        if let rawValue = getenv(MuxerConstants.usbmuxdEnvKey) {
            print("[minimuxer] getenv(USBMUXD_SOCKET_ADDRESS) =", String(cString: rawValue))
        } else {
            print("[minimuxer] WARN: USBMUXD_SOCKET_ADDRESS was not set")
        }
    }

    public static func start(pairingFile: String, logPath: String) throws {
        guard let pairingData = pairingFile.data(using: .utf8),
              let pairingDict = try? PropertyListSerialization.propertyList(
                from: pairingData,
                options: [],
                format: nil
              ) as? [String: Any],
              let pairingXml = try? PropertyListSerialization.data(
                fromPropertyList: pairingDict,
                format: .xml,
                options: 0
              ) else {
            print("[minimuxer] ERROR: Failed to parse pairing file")
            throw MinimuxerError.PairingFile
        }

        let remotePairing: Bool
        if pairingDict["private_key"] as? Data != nil {
            print("[minimuxer] INFO: RPPairing file detected")
            remotePairing = true
        } else if pairingDict["UDID"] as? String != nil {
            print("[minimuxer] INFO: Lockdown pairing file detected")
            remotePairing = false
        } else {
            print("[minimuxer] ERROR: Pairing file missing UDID")
            throw MinimuxerError.PairingFile
        }

        stateLock.lock()
        if _started {
            stateLock.unlock()
            print("[minimuxer] Already started minimuxer, skipping")
            return
        }
        generation &+= 1
        let startGeneration = generation
        cachedPairingDict = pairingDict
        cachedPairingXml = pairingXml
        _isrppairing = remotePairing
        _started = true
        _usbmuxdReady = remotePairing
        stateLock.unlock()

        do {
            if remotePairing {
                try RustIdevice.setRpPairingFile(pairingFile)
            } else {
                Thread.detachNewThread { listenLoop(generation: startGeneration) }
                Heartbeat.startBeat(generation: startGeneration)
            }
            print("[minimuxer] minimuxer has started!")
        } catch {
            reset()
            throw error
        }
    }

    /// Stops the current logical session and invalidates all background work.
    /// The listener owns its socket and will close it after `shutdown` wakes
    /// `accept()`, avoiding a double-close/reused-fd race.
    public static func reset() {
        stateLock.lock()
        generation &+= 1
        _started = false
        _usbmuxdReady = false
        _isrppairing = false
        cachedPairingDict = nil
        cachedPairingXml = nil
        currentDeviceIP = nil
        currentEvent = nil
        let fd = listenerFD
        listenerFD = nil
        stateLock.unlock()

        Heartbeat.reset()
        if let fd {
            _ = shutdown(fd, SHUT_RDWR)
        }
        print("[minimuxer] minimuxer state reset")
    }

    public static func isCurrentGeneration(_ candidate: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == candidate && _started
    }

    // MARK: - Listener

    private static func listenLoop(generation listenerGeneration: UInt64) {
        while isCurrentGeneration(listenerGeneration) {
            print("[minimuxer] Starting listener")

            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }

            stateLock.lock()
            if generation == listenerGeneration, _started {
                listenerFD = fd
                stateLock.unlock()
            } else {
                stateLock.unlock()
                close(fd)
                return
            }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            #if canImport(Darwin)
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            #endif

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = MuxerConstants.usbmuxdPort.bigEndian
            addr.sin_addr.s_addr = inet_addr(MuxerConstants.usbmuxdHost)

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if let rawValue = getenv(MuxerConstants.usbmuxdEnvKey) {
                print("[minimuxer] muxer: (ENV) USBMUXD_SOCKET_ADDRESS =", String(cString: rawValue))
            }

            guard bindResult == 0, listen(fd, 16) == 0 else {
                print("[minimuxer] WARN: Failed to bind/listen")
                close(fd)
                clearListenerFD(fd, generation: listenerGeneration)
                setReady(false, generation: listenerGeneration)
                if isCurrentGeneration(listenerGeneration) {
                    Thread.sleep(forTimeInterval: 1)
                }
                continue
            }

            print("[minimuxer] Bound successfully to \(MuxerConstants.usbmuxdHost):\(MuxerConstants.usbmuxdPort)")
            setReady(true, generation: listenerGeneration)

            var consecutiveErrors = 0
            while isCurrentGeneration(listenerGeneration) {
                var clientAddr = sockaddr()
                var addrLen = socklen_t(MemoryLayout<sockaddr>.size)
                let clientFd = accept(fd, &clientAddr, &addrLen)
                guard clientFd >= 0 else {
                    if errno == EINTR { continue }
                    if isCurrentGeneration(listenerGeneration) == false { break }
                    consecutiveErrors += 1
                    print("[minimuxer] WARN: accept() failed (\(consecutiveErrors)): \(String(cString: strerror(errno)))")
                    if consecutiveErrors >= 3 {
                        print("[minimuxer] ERROR: accept() repeatedly failing, restarting socket")
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                consecutiveErrors = 0

                #if canImport(Darwin)
                var nosig: Int32 = 1
                setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
                #endif

                Task.detached {
                    handleClient(fd: clientFd, generation: listenerGeneration)
                }
            }

            close(fd)
            clearListenerFD(fd, generation: listenerGeneration)
            setReady(false, generation: listenerGeneration)
            guard isCurrentGeneration(listenerGeneration) else { return }
            print("[minimuxer] listener restarting...")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private static func handleClient(fd: Int32, generation clientGeneration: UInt64) {
        defer { close(fd) }

        while isCurrentGeneration(clientGeneration) {
            guard let header = receiveExactly(fd: fd, count: RawPacket.headerSize),
                  let declaredSize = RawPacket.declaredSize(in: header),
                  declaredSize >= RawPacket.headerSize,
                  declaredSize <= RawPacket.maximumPacketSize else {
                return
            }

            let bodySize = declaredSize - RawPacket.headerSize
            let body: Data
            if bodySize == 0 {
                body = Data()
            } else {
                guard let receivedBody = receiveExactly(fd: fd, count: bodySize) else { return }
                body = receivedBody
            }

            var data = header
            data.append(body)
            guard let packet = RawPacket(data: data) else { return }

            do {
                let response = try handlePacket(packet, fd: fd, generation: clientGeneration)
                let responsePacket = RawPacket(
                    plist: response,
                    version: 1,
                    message: 8,
                    tag: packet.tag
                )
                guard sendAll(fd: fd, data: responsePacket.data) else { return }
            } catch {
                print("[minimuxer] WARN: usbmux client request failed: \(error)")
                return
            }
        }
    }

    private static func buildPayload(deviceIP: String, event: String? = nil) throws -> [String: Any] {
        guard let udid = pairingUDID() else {
            throw MinimuxerError.PairingFile
        }

        let networkAddr = convertIp(deviceIP)
        var payload: [String: Any] = [
            "DeviceID": 420,
            "Properties": [
                "ConnectionType": "Network",
                "DeviceID": 420,
                "EscapedFullServiceName": "\(udid)._apple-mobdev2._tcp.local",
                "InterfaceIndex": 69,
                "NetworkAddress": Data(networkAddr),
                "SerialNumber": udid
            ]
        ]

        if let event {
            payload["MessageType"] = event
        }
        return payload
    }

    // MARK: - Packet Handling

    private static func handlePacket(
        _ packet: RawPacket,
        fd: Int32,
        generation clientGeneration: UInt64
    ) throws -> [String: Any] {
        guard isCurrentGeneration(clientGeneration),
              let messageType = packet.plist["MessageType"] as? String else {
            throw MinimuxerError.NoConnection
        }

        print("[minimuxer] usbmux message:", messageType)

        switch messageType {
        case "ListDevices":
            guard let deviceIP = deviceStateSnapshot().ip,
                  let payload = try? buildPayload(deviceIP: deviceIP) else {
                return ["DeviceList": []]
            }
            return ["DeviceList": [payload]]

        case "Listen":
            let deviceState = deviceStateSnapshot()
            if let deviceIP = deviceState.ip,
               let event = deviceState.event {
                let payload = try buildPayload(deviceIP: deviceIP, event: event)
                let eventPacket = RawPacket(plist: payload, version: 1, message: 8, tag: 0)
                guard sendAll(fd: fd, data: eventPacket.data) else {
                    throw MinimuxerError.NoConnection
                }
            }
            return ["MessageType": "Result", "Number": 0]

        case "ReadBUID":
            return ["BUID": "00000000-0000-0000-0000-000000000000"]

        case "ReadPairRecord":
            return ["PairRecordData": pairingXMLSnapshot() ?? Data()]

        default:
            print("[minimuxer] WARN: unknown message type:", messageType)
            throw MinimuxerError.NoConnection
        }
    }

    public static func notifyDeviceAttached(deviceIP: String) {
        stateLock.lock()
        currentDeviceIP = deviceIP
        currentEvent = DEVICE_ATTACH
        stateLock.unlock()
    }

    public static func notifyDeviceDetached() {
        stateLock.lock()
        currentDeviceIP = nil
        currentEvent = DEVICE_DETACH
        stateLock.unlock()
    }

    // MARK: - Helpers

    private static func receiveExactly(fd: Int32, count: Int) -> Data? {
        guard count >= 0, count <= RawPacket.maximumPacketSize else { return nil }
        if count == 0 { return Data() }
        var data = Data(count: count)
        var offset = 0

        while offset < count {
            let readCount: Int = data.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return -1 }
                return recv(fd, base.advanced(by: offset), count - offset, 0)
            }
            if readCount > 0 {
                offset += readCount
                continue
            }
            if readCount < 0, errno == EINTR { continue }
            return nil
        }
        return data
    }

    private static func sendAll(fd: Int32, data: Data) -> Bool {
        guard data.isEmpty == false else { return false }
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < data.count {
                let sent = send(fd, base.advanced(by: offset), data.count - offset, 0)
                if sent > 0 {
                    offset += sent
                    continue
                }
                if sent < 0, errno == EINTR { continue }
                return false
            }
            return true
        }
    }

    private static func stateSnapshot() -> (started: Bool, ready: Bool, remotePairing: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (_started, _usbmuxdReady, _isrppairing)
    }

    private static func setReady(_ ready: Bool, generation candidate: UInt64) {
        stateLock.lock()
        if generation == candidate, _started {
            _usbmuxdReady = ready
        }
        stateLock.unlock()
    }

    private static func clearListenerFD(_ fd: Int32, generation candidate: UInt64) {
        stateLock.lock()
        if generation == candidate, listenerFD == fd {
            listenerFD = nil
        }
        stateLock.unlock()
    }

    private static func pairingUDID() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedPairingDict?["UDID"] as? String
    }

    private static func pairingXMLSnapshot() -> Data? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedPairingXml
    }

    private static func deviceStateSnapshot() -> (ip: String?, event: String?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (currentDeviceIP, currentEvent)
    }

    private static func convertIp(_ ip: String) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 152)
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return data }
        data[0] = 10
        data[1] = 0x02
        let ipBytes = withUnsafeBytes(of: &addr.s_addr) { Array($0) }
        for (index, byte) in ipBytes.enumerated() {
            data[4 + index] = byte
        }
        return data
    }
}
