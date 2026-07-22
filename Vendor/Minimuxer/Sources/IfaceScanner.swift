//
//  IfaceScanner.swift
//  Minimuxer
//
//  Created by ny on 2/27/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - IPv4 helpers

@inline(__always)
private func ipv4String(_ value: UInt32) -> String? {
    var addr = in_addr(s_addr: value.bigEndian)
    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &addr, &buffer, UInt32(INET_ADDRSTRLEN)) != nil else {
        return nil
    }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

@inline(__always)
private func sockaddrIPv4(_ address: inout sockaddr) -> UInt32? {
    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    #if canImport(Darwin)
    let addressLength = socklen_t(address.sa_len)
    #else
    let addressLength = socklen_t(MemoryLayout<sockaddr>.size)
    #endif

    guard getnameinfo(
        &address,
        addressLength,
        &buffer,
        socklen_t(buffer.count),
        nil,
        0,
        NI_NUMERICHOST
    ) == 0 else {
        return nil
    }

    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    let string = String(decoding: bytes, as: UTF8.self)
    var parsed = in_addr()
    return inet_pton(AF_INET, string, &parsed) == 1 ? parsed.s_addr.bigEndian : nil
}

// MARK: - NetInfo

public struct NetInfo: Hashable, CustomStringConvertible, Sendable {
    public let name: String
    public let hostIP: String
    public let maskIP: String

    fileprivate let host: UInt32
    fileprivate let mask: UInt32

    init?(ifa: ifaddrs) {
        guard let name = String(utf8String: ifa.ifa_name),
              var address = ifa.ifa_addr?.pointee,
              var netmask = ifa.ifa_netmask?.pointee,
              let host = sockaddrIPv4(&address),
              let mask = sockaddrIPv4(&netmask),
              let hostString = ipv4String(host),
              let maskString = ipv4String(mask)
        else {
            return nil
        }

        self.name = name
        self.host = host
        self.mask = mask
        hostIP = hostString
        maskIP = maskString
    }

    var peerIP: String? {
        IfaceScanner.shared.getPeer(for: self)
    }

    var networkBase: UInt32 { host & mask }
    var broadcast: UInt32 { networkBase | ~mask }

    public var description: String {
        "\(name) | ip=\(hostIP) mask=\(maskIP)"
    }
}

public final class TunnelConfigBinding: Sendable {
    public let setDeviceIP: @Sendable (String?) -> Void
    public let setFakeIP: @Sendable (String?) -> Void
    public let setSubnetMask: @Sendable (String?) -> Void
    public let getOverrideFakeIP: @Sendable () -> String
    public let setOverrideEffective: @Sendable (Bool) -> Void

    public init(
        setDeviceIP: @escaping @Sendable (String?) -> Void,
        setFakeIP: @escaping @Sendable (String?) -> Void,
        setSubnetMask: @escaping @Sendable (String?) -> Void,
        getOverrideFakeIP: @escaping @Sendable () -> String,
        setOverrideEffective: @escaping @Sendable (Bool) -> Void
    ) {
        self.setDeviceIP = setDeviceIP
        self.setFakeIP = setFakeIP
        self.setSubnetMask = setSubnetMask
        self.getOverrideFakeIP = getOverrideFakeIP
        self.setOverrideEffective = setOverrideEffective
    }
}

final class IfaceScanner: @unchecked Sendable {
    static let shared = IfaceScanner()

    private let lock = NSLock()
    private var interfaces = Set<NetInfo>()
    private var refreshed = false
    private var tunnelConfig: TunnelConfigBinding?

    private init() {}

    func bindTunnelConfig(_ binding: TunnelConfigBinding) {
        lock.lock()
        tunnelConfig = binding
        lock.unlock()

        NetworkObserver.shared.refreshEndpoint()
    }

    var cachedOverrideFakeIP: String? {
        lock.lock()
        let binding = tunnelConfig
        lock.unlock()
        return binding?.getOverrideFakeIP()
    }

    func refresh() {
        let scannedInterfaces = Self.scan()

        lock.lock()
        interfaces = scannedInterfaces
        refreshed = true
        let binding = tunnelConfig
        lock.unlock()

        let vpnInterface = scannedInterfaces.first { $0.name.hasPrefix("utun") }
        let overrideIP = binding?.getOverrideFakeIP()
        let peerIP = overrideIP.flatMap { candidate in
            Minimuxer.testDeviceConnection(ifaddr: candidate) ? candidate : nil
        }
        let isOverrideActive = peerIP != nil && peerIP == overrideIP

        binding?.setDeviceIP(vpnInterface?.hostIP)
        binding?.setSubnetMask(vpnInterface?.maskIP)
        binding?.setFakeIP(peerIP)
        binding?.setOverrideEffective(isOverrideActive)

        print("""
        [minimuxer] [iface] rescan routes
          • interfaces: \(scannedInterfaces.count)
          • vpn host: \(vpnInterface?.hostIP ?? "nil")
          • vpn mask: \(vpnInterface?.maskIP ?? "nil")
          • vpn peer: \(peerIP ?? "nil")
          • cachedOverrideFakeIP: \(overrideIP ?? "nil")
          • overrideEffective: \(isOverrideActive)
          • refreshed: true
        """)
    }

    public func getPeer(for interface: NetInfo) -> String? {
        _ = interface
        guard let overrideIP = cachedOverrideFakeIP else {
            print("[minimuxer] [iface] no override peer configured")
            return nil
        }

        guard Minimuxer.testDeviceConnection(ifaddr: overrideIP) else {
            print("[minimuxer] [iface] override peer NOT reachable at:", overrideIP)
            return nil
        }

        print("[minimuxer] [iface] override peer reachable at:", overrideIP)
        return overrideIP
    }

    func probableVPN() throws -> NetInfo? {
        try snapshot().first { $0.name.hasPrefix("utun") }
    }

    func probableLAN() throws -> NetInfo? {
        try snapshot().first { $0.name.hasPrefix("en") }
    }

    func vpnPatched() -> Bool {
        guard let lan = try? probableLAN(),
              let vpn = try? probableVPN()
        else {
            return false
        }
        return lan.maskIP == vpn.maskIP
    }

    private func snapshot() throws -> Set<NetInfo> {
        lock.lock()
        defer { lock.unlock() }
        guard refreshed else {
            throw IfaceError.notRefreshed
        }
        return interfaces
    }

    private static func scan() -> Set<NetInfo> {
        print("[minimuxer] [iface] scan requested...")

        var result = Set<NetInfo>()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return result
        }
        defer { freeifaddrs(head) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            let isIPv4 = entry.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET)
            let up = Int32(IFF_UP)
            let running = Int32(IFF_RUNNING)
            let loopback = Int32(IFF_LOOPBACK)
            let isActive = (flags & (up | running | loopback)) == (up | running)

            if isIPv4, isActive, let info = NetInfo(ifa: entry) {
                print("[minimuxer] [iface]", info)
                result.insert(info)
            }
            current = entry.ifa_next
        }

        print("[minimuxer] [iface] total:", result.count)
        return result
    }
}

enum IfaceError: Error {
    case notRefreshed
}
