import CryptoKit
import Foundation
@preconcurrency import AltSign

protocol AnisetteProvider: Sendable {
    func fetch() async throws -> ALTAnisetteData
    func resetProvisioning() async
}

protocol AnisetteEnvironmentManaging: AnisetteProvider {
    func availableServers() async -> [AnisetteServer]
    func selectedServerID() async -> String?
    func selectServer(id: String) async
}

enum AnisetteV3Error: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidServerResponse
    case provisioningFailed
    case staleProvisioning
    case unavailable
}

struct AnisetteProvisioningState: Codable, Equatable, Sendable {
    let identifier: String
    let adiPB: String

    init?(identifier: String, adiPB: String) {
        guard identifier.isEmpty == false, adiPB.isEmpty == false else { return nil }
        self.identifier = identifier
        self.adiPB = adiPB
    }
}

struct AnisetteV3Identity: Equatable, Sendable {
    let encodedIdentifier: String
    let localUserID: String
    let deviceIdentifier: String

    init(bytes: Data) throws {
        guard bytes.count == 16 else {
            throw AnisetteV3Error.invalidIdentifier
        }

        encodedIdentifier = bytes.base64EncodedString()
        localUserID = SHA256.hash(data: bytes)
            .map { String(format: "%02X", $0) }
            .joined()

        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        deviceIdentifier = [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            String(hex.dropFirst(12).prefix(4)),
            String(hex.dropFirst(16).prefix(4)),
            String(hex.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }
}
