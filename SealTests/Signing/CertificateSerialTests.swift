import Testing
@testable import Seal

struct CertificateSerialTests {
    @Test
    func leadingZeroDoesNotChangeCertificateIdentity() {
        #expect(
            CertificateSerial.matches(
                "492CEFA41CB31633BDE03BED94193D9",
                "0492CEFA41CB31633BDE03BED94193D9"
            )
        )
    }

    @Test
    func acceptsCasePrefixAndCommonSeparators() {
        #expect(CertificateSerial.matches("0x00:aa-bb cc", "AABBCC"))
        #expect(CertificateSerial.canonical("0000") == "0")
    }

    @Test
    func rejectsNonSerialDisplayLabelsAndMissingValues() {
        #expect(CertificateSerial.canonical("Seal-D94193D9") == nil)
        #expect(CertificateSerial.matches(nil, "A1") == false)
        #expect(CertificateSerial.matches("", "A1") == false)
    }
}
