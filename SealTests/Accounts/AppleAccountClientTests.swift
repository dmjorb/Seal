import Foundation
import Testing
@testable import Seal

struct AppleAccountClientTests {
    @Test
    func masksEmailWithoutPersistingTheFullAddress() {
        #expect(AppleAccountClient.mask("seal.user@icloud.com") == "sea***er@icloud.com")
        #expect(AppleAccountClient.mask("developer@icloud.com") == "dev***er@icloud.com")
        #expect(AppleAccountClient.mask("13812345678") == "138****5678")
        #expect(AppleAccountClient.mask("+8613812345678") == "+86 138****5678")
        #expect(AppleAccountClient.mask("+14155552671") == "+1 415****2671")
        #expect(AppleAccountClient.mask("invalid") == "inv***id")
    }

    @Test
    func teamLookupFailureDoesNotExposeRawAppleTechnicalDetails() {
        let error = NSError(
            domain: "com.apple.authentication",
            code: -20101,
            userInfo: [NSLocalizedDescriptionKey: "Developer services are unavailable"]
        )

        let failure = AppleAuthenticationFailure.make(
            stage: .teamLookup,
            error: error
        )

        #expect(failure.code == "SEAL-AUTH-105")
        #expect(failure.reason.contains("-20101") == false)
        #expect(failure.reason.contains("Developer services are unavailable") == false)
        #expect(failure.reason.contains("开发团队"))
    }
}
