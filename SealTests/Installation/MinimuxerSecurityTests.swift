import Foundation
import Minimuxer
import Testing

@Suite(.serialized)
struct MinimuxerSecurityTests {
    @Test
    func legacyStartNeverCachesPairingOrStartsListener() throws {
        Minimuxer.stop()
        defer { Minimuxer.stop() }

        do {
            try Minimuxer.start(
                pairingFile: try pairingXML([
                    "UDID": "legacy-device",
                    "HostID": "host",
                    "HostPrivateKey": Data(repeating: 7, count: 32)
                ]),
                logPath: NSTemporaryDirectory()
            )
            Issue.record("Expected legacy pairing rejection")
        } catch let error as MinimuxerError {
            guard case .LegacyPairingUnsupported = error else {
                Issue.record("Unexpected Minimuxer error: \(error)")
                return
            }
        }

        let snapshot = Minimuxer.securitySnapshot()
        #expect(snapshot.isListenerActive == false)
        #expect(snapshot.cachedPairingByteCount == 0)
        #expect(snapshot.rustHasPairingFile == false)
        #expect(snapshot.rustHasCachedConnection == false)
    }

    @Test
    func readPairRecordProductionPolicyAlwaysDeniesAccess() {
        #expect(PairRecordAccessPolicy.pairRecordData() == nil)
    }

    @Test
    func remotePairingCanBeReplacedThenClearedWithoutConnectingToDevice() throws {
        Minimuxer.stop()
        defer { Minimuxer.stop() }
        let initialGeneration = Minimuxer.securitySnapshot().pairingGeneration

        try Minimuxer.setRemotePairingFile(
            try remotePairingXML(
                privateKeyBase64: "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A=",
                publicKeyBase64: "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=",
                identifier: "first"
            )
        )
        let first = Minimuxer.securitySnapshot()
        #expect(first.rustHasPairingFile)
        #expect(first.pairingGeneration == initialGeneration + 1)

        try Minimuxer.setRemotePairingFile(
            try remotePairingXML(
                privateKeyBase64: "TM0Imyj/ltqdtsNG7BFOD1uKMZ81q6Yk2oz27U+4pvs=",
                publicKeyBase64: "PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw=",
                identifier: "second"
            )
        )
        let replacement = Minimuxer.securitySnapshot()
        #expect(replacement.rustHasPairingFile)
        #expect(replacement.rustHasCachedConnection == false)
        #expect(replacement.pairingGeneration == first.pairingGeneration + 1)

        Minimuxer.stop()
        let cleared = Minimuxer.securitySnapshot()
        #expect(cleared.isListenerActive == false)
        #expect(cleared.cachedPairingByteCount == 0)
        #expect(cleared.rustHasPairingFile == false)
        #expect(cleared.rustHasCachedConnection == false)
    }

    private func remotePairingXML(
        privateKeyBase64: String,
        publicKeyBase64: String,
        identifier: String
    ) throws -> String {
        try pairingXML([
            "private_key": try #require(Data(base64Encoded: privateKeyBase64)),
            "public_key": try #require(Data(base64Encoded: publicKeyBase64)),
            "identifier": identifier
        ])
    }

    private func pairingXML(_ dictionary: [String: Any]) throws -> String {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        return try #require(String(data: data, encoding: .utf8))
    }
}
