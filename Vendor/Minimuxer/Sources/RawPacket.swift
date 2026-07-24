//
//  RawPacket.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation

public class RawPacket {
    public static let headerSize = 16
    public static let maximumPacketSize = 16 * 1024 * 1024

    public let version: UInt32
    public let message: UInt32
    public let tag: UInt32
    public let plist: [String: Any]

    public init?(data: Data) {
        guard data.count >= Self.headerSize,
              let declaredSize = Self.declaredSize(in: data),
              declaredSize >= Self.headerSize,
              declaredSize <= Self.maximumPacketSize,
              data.count >= declaredSize,
              let version = Self.uint32LE(in: data, offset: 4),
              let message = Self.uint32LE(in: data, offset: 8),
              let tag = Self.uint32LE(in: data, offset: 12) else {
            return nil
        }

        let plistData = data.subdata(in: Self.headerSize..<declaredSize)
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        self.version = version
        self.message = message
        self.tag = tag
        self.plist = plist
    }

    public init(plist: [String: Any], version: UInt32, message: UInt32, tag: UInt32) {
        self.plist = plist
        self.version = version
        self.message = message
        self.tag = tag
    }

    public static func declaredSize(in data: Data) -> Int? {
        guard let value = uint32LE(in: data, offset: 0) else { return nil }
        return Int(value)
    }

    public var data: Data {
        guard let plistData = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ), plistData.count <= Self.maximumPacketSize - Self.headerSize else {
            return Data()
        }

        var packetData = Data()
        var size = UInt32(Self.headerSize + plistData.count).littleEndian
        var ver = version.littleEndian
        var msg = message.littleEndian
        var t = tag.littleEndian

        packetData.append(withUnsafeBytes(of: &size) { Data($0) })
        packetData.append(withUnsafeBytes(of: &ver) { Data($0) })
        packetData.append(withUnsafeBytes(of: &msg) { Data($0) })
        packetData.append(withUnsafeBytes(of: &t) { Data($0) })
        packetData.append(plistData)

        return packetData
    }

    private static func uint32LE(in data: Data, offset: Int) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }
    }
}
