import Foundation
import Testing
@testable import Seal

struct X509CertificateValidityReaderTests {
    @Test
    func readsUTCTimeValidityFromDERCertificate() throws {
        let der = certificate(
            notBeforeTag: 0x17,
            notBefore: "260101000000Z",
            notAfterTag: 0x17,
            notAfter: "270101000000Z"
        )

        let validity = try #require(X509CertificateValidityReader.validity(from: der))
        #expect(utcComponents(validity.notBefore) == [2026, 1, 1, 0, 0, 0])
        #expect(utcComponents(validity.notAfter) == [2027, 1, 1, 0, 0, 0])
    }

    @Test
    func readsGeneralizedTimeAndPEMEncoding() throws {
        let der = certificate(
            notBeforeTag: 0x18,
            notBefore: "20510101000000Z",
            notAfterTag: 0x18,
            notAfter: "20520101000000Z"
        )
        let pem = """
        -----BEGIN CERTIFICATE-----
        \(der.base64EncodedString(options: .lineLength64Characters))
        -----END CERTIFICATE-----
        """.data(using: .utf8)!

        let validity = try #require(X509CertificateValidityReader.validity(from: pem))
        #expect(utcComponents(validity.notBefore).first == 2051)
        #expect(utcComponents(validity.notAfter).first == 2052)
    }

    @Test
    func utcTimeUsesRFC5280CenturyBoundary() throws {
        let der = certificate(
            notBeforeTag: 0x17,
            notBefore: "500101000000Z",
            notAfterTag: 0x17,
            notAfter: "490101000000Z"
        )
        let validity = try #require(X509CertificateValidityReader.validity(from: der))
        #expect(utcComponents(validity.notBefore).first == 1950)
        #expect(utcComponents(validity.notAfter).first == 2049)
    }

    private func certificate(
        notBeforeTag: UInt8,
        notBefore: String,
        notAfterTag: UInt8,
        notAfter: String
    ) -> Data {
        let version = tlv(0xA0, tlv(0x02, Data([0x02])))
        let serial = tlv(0x02, Data([0x01]))
        let signature = tlv(0x30, Data())
        let issuer = tlv(0x30, Data())
        let validity = tlv(
            0x30,
            tlv(notBeforeTag, Data(notBefore.utf8))
                + tlv(notAfterTag, Data(notAfter.utf8))
        )
        let subject = tlv(0x30, Data())
        let subjectPublicKeyInfo = tlv(0x30, Data())
        let tbs = tlv(
            0x30,
            version + serial + signature + issuer + validity + subject + subjectPublicKeyInfo
        )
        return tlv(0x30, tbs + signature + tlv(0x03, Data([0x00])))
    }

    private func tlv(_ tag: UInt8, _ value: Data) -> Data {
        Data([tag]) + length(value.count) + value
    }

    private func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var value = count
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private func utcComponents(_ date: Date) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let values = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return [
            values.year,
            values.month,
            values.day,
            values.hour,
            values.minute,
            values.second
        ].compactMap { $0 }
    }
}
