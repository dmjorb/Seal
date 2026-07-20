import Foundation
import Testing
@testable import Seal

struct LocalDevVPNLinkTests {
    @Test
    func enableLinkStartsLocalDevVPNAndReturnsToSeal() {
        #expect(
            LocalDevVPNLink.enableAndReturn.absoluteString
                == "localdevvpn://enable?scheme=seal"
        )
    }

    @Test
    func disableLinkStopsLocalDevVPNAndReturnsToSeal() {
        #expect(
            LocalDevVPNLink.disableAndReturn.absoluteString
                == "localdevvpn://disable?scheme=seal"
        )
    }

    @Test
    func callbackRecognizesOnlySealURLs() {
        #expect(LocalDevVPNLink.isCallback(URL(string: "seal://")!))
        #expect(LocalDevVPNLink.isCallback(URL(string: "localdevvpn://")!) == false)
    }
}
