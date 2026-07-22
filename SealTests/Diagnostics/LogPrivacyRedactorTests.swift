import Testing
@testable import Seal

struct LogPrivacyRedactorTests {
    @Test
    func redactsAuthenticationHeadersCookiesAndJWTs() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature0123456789"
        let raw = "Authorization: Bearer \(jwt)\nCookie: session=super-secret-cookie"
        let redacted = LogPrivacyRedactor.redact(raw)

        #expect(redacted.contains("Authorization: [redacted]"))
        #expect(redacted.contains("Cookie: [redacted]"))
        #expect(redacted.contains(jwt) == false)
        #expect(redacted.contains("super-secret-cookie") == false)
    }

    @Test
    func redactsTeamSerialUDIDAndHyphenatedUUID() {
        let uuid = "123E4567-E89B-12D3-A456-426614174000"
        let raw = "Team ID: ABCDE12345 Serial=112233AABBCC UDID: 00008110-0012345678901234 profile UUID: \(uuid)"
        let redacted = LogPrivacyRedactor.redact(raw)

        #expect(redacted.contains("ABCDE12345") == false)
        #expect(redacted.contains("112233AABBCC") == false)
        #expect(redacted.contains("00008110-0012345678901234") == false)
        #expect(redacted.contains(uuid) == false)
    }

    @Test
    func redactsLongBase64LikeTokens() {
        let token = "QWxhZGRpbjpvcGVuIHNlc2FtZSB0b2tlbiAxMjM0NTY3ODkw"
        let redacted = LogPrivacyRedactor.redact("payload=\(token)")

        #expect(redacted.contains(token) == false)
        #expect(redacted.contains("…"))
    }
}
