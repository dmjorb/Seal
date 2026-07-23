import Foundation
import Testing
@testable import Seal

struct AppleServiceFailurePolicyTests {
    @Test(arguments: [
        (AccountStatus.verified, "verified", true),
        (AccountStatus.availableOffline, "availableOffline", true),
        (AccountStatus.needsVerification, "needsVerification", false)
    ])
    func accountStatusPersistenceValuesRemainStable(
        status: AccountStatus,
        rawValue: String,
        isSelectable: Bool
    ) {
        #expect(status.rawValue == rawValue)
        #expect(AccountStatus(rawValue: rawValue) == status)
        #expect(status.isSelectable == isSelectable)
    }

    @Test
    func networkFailureNeverRequiresAccountReverification() {
        let failure = AppleServiceFailurePolicy.networkFailure(
            underlying: URLError(.notConnectedToInternet)
        )
        #expect(failure.code.hasPrefix("SEAL-NET-"))
        #expect(AppleServiceFailurePolicy.shouldRequireReverification(failure) == false)
        #expect(AppleServiceFailurePolicy.isNetworkError(URLError(.timedOut)))
        #expect(AppleServiceFailurePolicy.isNetworkError(URLError(.dnsLookupFailed)))
    }

    @Test
    func onlyExplicitAuthenticationFailuresRequireReverification() {
        let authenticationFailure = ImportFailure(
            title: "账号需要重新验证",
            reason: "认证状态失效",
            recovery: "重新验证 Apple ID",
            code: "SEAL-AUTH-105"
        )
        let genericFailure = ImportFailure(
            title: "请求失败",
            reason: "未知错误",
            recovery: "重试",
            code: "SEAL-AUTH-107"
        )
        #expect(AppleServiceFailurePolicy.shouldRequireReverification(authenticationFailure))
        #expect(AppleServiceFailurePolicy.shouldRequireReverification(genericFailure) == false)
    }

    @Test
    func legacyMislabelWithLocalSecretBecomesOfflineAvailable() {
        let account = AppleAccountRecord(
            maskedEmail: "a***@icloud.com",
            accountIdentifier: "account",
            teamID: "TEAM",
            teamName: "Team",
            status: .needsVerification,
            lastVerifiedAt: Date()
        )
        #expect(
            AccountAvailabilityPolicy.repairedStatus(for: account, hasLocalSecret: true)
                == .availableOffline
        )
        #expect(
            AccountAvailabilityPolicy.repairedStatus(for: account, hasLocalSecret: false)
                == .needsVerification
        )
    }

    @Test
    func offlineAvailableAccountRemainsSelectable() {
        let account = AppleAccountRecord(
            maskedEmail: "a***@icloud.com",
            accountIdentifier: "account",
            teamID: "TEAM",
            teamName: "Team",
            status: .availableOffline,
            lastVerifiedAt: Date()
        )
        #expect(AccountAvailabilityPolicy.isSelectable(account))
    }
}
