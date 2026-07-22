import Foundation
import Testing
@testable import Seal

struct AccountFailureClassifierTests {
    @Test
    func offlineAndTimeoutRemainTransient() {
        #expect(AccountFailureClassifier.disposition(for: URLError(.notConnectedToInternet)) == .transient)
        #expect(AccountFailureClassifier.disposition(for: URLError(.timedOut)) == .transient)
        #expect(AccountFailureClassifier.disposition(for: URLError(.networkConnectionLost)) == .transient)
    }

    @Test
    func transientFailureDoesNotUseAuthenticationCode() {
        let failure = AccountFailureClassifier.transientFailure(from: URLError(.notConnectedToInternet))
        #expect(failure.code == "SEAL-NET-101")
        #expect(failure.title == "无法连接网络")
        #expect(AccountFailureClassifier.disposition(for: failure) == .transient)
    }

    @Test
    func explicitCredentialLossRequiresAuthentication() {
        let missingCredential = ImportFailure(
            title: "账号需要验证",
            reason: "本机没有当前 Apple ID 的登录凭据。",
            recovery: "重新验证 Apple ID",
            code: "SEAL-AUTH-105"
        )
        #expect(AccountFailureClassifier.disposition(for: missingCredential) == .authentication)
    }

    @Test
    func unrelatedSigningFailureDoesNotInvalidateAccount() {
        let failure = ImportFailure(
            title: "签名失败",
            reason: "IPA 文件损坏",
            recovery: "重新导入 IPA",
            code: "SEAL-SIGN-500"
        )
        #expect(AccountFailureClassifier.disposition(for: failure) == .other)
    }
}
