import Foundation
import Testing
@testable import Seal

struct AnisetteV3ClientTests {
    @Test
    func officialServersPutSelectedServerFirstWithoutDuplicates() throws {
        let selected = try #require(AnisetteServerCatalog.official.first)
        let servers = AnisetteServerCatalog.prioritized(selectedID: selected.id)

        #expect(servers.first?.id == selected.id)
        #expect(Set(servers.map(\.id)).count == servers.count)
        #expect(Set(servers.map(\.id)) == Set(AnisetteServerCatalog.official.map(\.id)))
        #expect(servers.allSatisfy { $0.url.scheme == "https" })
    }

    @Test
    func unknownSelectedServerUsesOfficialDefaultOrder() {
        let servers = AnisetteServerCatalog.prioritized(selectedID: "not-a-server")

        #expect(servers == AnisetteServerCatalog.official)
    }

    @Test
    func provisioningStateRoundTripsAndRejectsEmptyValues() throws {
        let state = AnisetteProvisioningState(identifier: "identifier", adiPB: "adi-pb")
        let data = try JSONEncoder().encode(state)

        #expect(try JSONDecoder().decode(AnisetteProvisioningState.self, from: data) == state)
        #expect(AnisetteProvisioningState(identifier: "", adiPB: "adi-pb") == nil)
        #expect(AnisetteProvisioningState(identifier: "identifier", adiPB: "") == nil)
    }

    @Test
    func identityDerivationIsStableForSixteenBytes() throws {
        let bytes = Data((0..<16).map(UInt8.init))
        let identity = try AnisetteV3Identity(bytes: bytes)

        #expect(identity.encodedIdentifier == "AAECAwQFBgcICQoLDA0ODw==")
        #expect(identity.localUserID == "BE45CB2605BF36BEBDE684841A28F0FD43C69850A3DCE5FEDBA69928EE3A8991")
        #expect(identity.deviceIdentifier == "00010203-0405-0607-0809-0A0B0C0D0E0F")
    }

    @Test
    func identityDerivationRejectsWrongByteCount() {
        #expect(throws: AnisetteV3Error.invalidIdentifier) {
            _ = try AnisetteV3Identity(bytes: Data([0]))
        }
    }

    @Test
    func clientInfoParsingRequiresBothServerValues() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "client_info": "<MacBookPro>",
            "user_agent": "com.apple.dt.Xcode/1"
        ])

        #expect(
            try AnisetteV3Client.parseClientInfo(data: data) ==
                AnisetteV3ClientInfo(
                    clientInfo: "<MacBookPro>",
                    userAgent: "com.apple.dt.Xcode/1"
                )
        )
    }

    @Test
    func clientInfoParsingRejectsIncompleteResponse() throws {
        let data = try JSONSerialization.data(withJSONObject: ["client_info": "only-one"])

        #expect(throws: AnisetteV3Error.invalidServerResponse) {
            _ = try AnisetteV3Client.parseClientInfo(data: data)
        }
    }

    @Test
    func clientInfoParsingNormalizesMalformedJSON() {
        let data = Data("not-json".utf8)

        #expect(throws: AnisetteV3Error.invalidServerResponse) {
            _ = try AnisetteV3Client.parseClientInfo(data: data)
        }
    }

    @Test
    func resetSigningEnvironmentRemovesProvisioningAndIdentifier() async throws {
        let store = TestAnisetteProvisioningStore()
        try await store.saveIdentifier("identifier")
        try await store.save(AnisetteProvisioningState(identifier: "identifier", adiPB: "adi-pb")!)
        let client = AnisetteV3Client(store: store)

        await client.resetProvisioning()

        let identifier = try await store.loadIdentifier()
        let state = try await store.load()
        #expect(identifier == nil)
        #expect(state == nil)
    }
}

private actor TestAnisetteProvisioningStore: AnisetteProvisioningStore {
    private var identifier: String?
    private var state: AnisetteProvisioningState?

    func loadIdentifier() async throws -> String? { identifier }

    func saveIdentifier(_ identifier: String) async throws {
        self.identifier = identifier
    }

    func removeIdentifier() async throws {
        identifier = nil
    }

    func load() async throws -> AnisetteProvisioningState? { state }

    func save(_ state: AnisetteProvisioningState) async throws {
        self.state = state
    }

    func remove() async throws {
        state = nil
    }
}
