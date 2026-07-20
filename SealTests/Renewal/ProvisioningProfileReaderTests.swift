import Foundation
import Testing
@testable import Seal

struct ProvisioningProfileReaderTests {
    @Test
    func readsExpirationDateFromEmbeddedPlist() throws {
        let expiration = Date(timeIntervalSince1970: 2_000_000_000)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["ExpirationDate": expiration],
            format: .xml,
            options: 0
        )
        var profile = Data("binary-prefix".utf8)
        profile.append(plist)
        profile.append(Data("binary-suffix".utf8))

        #expect(try ProvisioningProfileReader().expirationDate(from: profile) == expiration)
    }

    @Test
    func returnsNilWhenProfileContainsNoPlist() throws {
        #expect(
            try ProvisioningProfileReader().expirationDate(from: Data([0x01, 0x02])) == nil
        )
    }
}
