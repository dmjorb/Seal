import Foundation
@preconcurrency import AltSign

enum AppleAuthenticationStage: Sendable {
    case signIn
    case teamLookup
}

enum AppleAuthenticationFailure {
    static func make(stage: AppleAuthenticationStage, error: Error) -> ImportFailure {
        let nsError = error as NSError
        let diagnostic = "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"

        switch stage {
        case .signIn:
            return ImportFailure(
                title: "Unable to add account",
                reason: "Apple sign-in failed. \(diagnostic)",
                recovery: "Retry",
                code: "SEAL-AUTH-107"
            )
        case .teamLookup:
            return ImportFailure(
                title: "Unable to add account",
                reason: "The verification code was accepted, but Apple could not load the developer team. \(diagnostic)",
                recovery: "Retry",
                code: "SEAL-AUTH-105"
            )
        }
    }
}

@MainActor
final class AppleAccountClient {
    private let anisetteProvider: any AnisetteProvider

    init(anisetteProvider: any AnisetteProvider = AnisetteV3Client()) {
        self.anisetteProvider = anisetteProvider
    }

    func authenticate(
        email: String,
        password: String,
        verificationCode: @escaping @MainActor @Sendable () async -> String?
    ) async throws -> AuthenticatedAppleAccount {
        do {
            return try await authenticateOnce(
                email: email,
                password: password,
                verificationCode: verificationCode
            )
        } catch ALTAppleAPIError.invalidAnisetteData {
            await anisetteProvider.resetProvisioning()
            do {
                return try await authenticateOnce(
                    email: email,
                    password: password,
                    verificationCode: verificationCode
                )
            } catch let failure as ImportFailure {
                throw failure
            } catch {
                throw Self.failure(from: error)
            }
        }
    }

    private func authenticateOnce(
        email: String,
        password: String,
        verificationCode: @escaping @MainActor @Sendable () async -> String?
    ) async throws -> AuthenticatedAppleAccount {
        var stage: AppleAuthenticationStage = .signIn
        do {
            try Task.checkCancellation()
            let anisetteData = try await anisetteProvider.fetch()
            let auth = try await authenticate(
                email: email,
                password: password,
                anisetteData: anisetteData,
                verificationCode: verificationCode
            ).value
            try Task.checkCancellation()
            stage = .teamLookup
            let teams = try await fetchTeams(
                account: auth.account,
                session: auth.session
            )
            try Task.checkCancellation()
            guard let team = teams.first(where: {
                $0.type != .free && $0.type != .unknown
            }) ?? teams.first(where: { $0.type == .free }) else {
                throw ImportFailure(
                    title: "无法添加账号",
                    reason: "未找到开发团队",
                    recovery: "检查 Apple ID",
                    code: "SEAL-AUTH-103"
                )
            }

            let id = UUID()
            let record = AppleAccountRecord(
                id: id,
                maskedEmail: Self.mask(email),
                accountIdentifier: auth.account.identifier,
                teamID: team.identifier,
                teamName: team.name,
                isFreeTeam: team.type == .free,
                lastVerifiedAt: Date()
            )
            let secret = AccountSecret(
                email: email,
                accountIdentifier: auth.account.identifier,
                dsid: auth.session.dsid,
                authToken: auth.session.authToken
            )
            return AuthenticatedAppleAccount(record: record, secret: secret)
        } catch is CancellationError {
            throw CancellationError()
        } catch ALTAppleAPIError.incorrectVerificationCode {
            throw ImportFailure(
                title: "无法添加账号",
                reason: "验证码无效",
                recovery: "重试",
                code: "SEAL-AUTH-101"
            )
        } catch ALTAppleAPIError.incorrectCredentials {
            throw ImportFailure(
                title: "无法添加账号",
                reason: "Apple ID 或密码无效",
                recovery: "重试",
                code: "SEAL-AUTH-102"
            )
        } catch ALTAppleAPIError.invalidAnisetteData {
            throw ALTAppleAPIError(.invalidAnisetteData)
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            if error is AnisetteV3Error {
                throw Self.failure(from: error)
            }
            throw AppleAuthenticationFailure.make(stage: stage, error: error)
        }
    }

    func validate(
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws {
        do {
            try Task.checkCancellation()
            let anisetteData = try await anisetteProvider.fetch()
            let session = ALTAppleAPISession(
                dsid: secret.dsid,
                authToken: secret.authToken,
                anisetteData: anisetteData
            )
            let altAccount = ALTAccount()
            altAccount.appleID = secret.email
            altAccount.identifier = secret.accountIdentifier
            let teams = try await fetchTeams(account: altAccount, session: session)
            try Task.checkCancellation()
            guard teams.contains(where: { $0.identifier == account.teamID }) else {
                throw ImportFailure(
                    title: "账号需要验证",
                    reason: "开发团队不可用",
                    recovery: "重新验证账号",
                    code: "SEAL-AUTH-104"
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw ImportFailure(
                title: "账号需要验证",
                reason: "Apple ID 会话已失效",
                recovery: "重新验证账号",
                code: "SEAL-AUTH-104"
            )
        }
    }

    nonisolated static func mask(_ appleID: String) -> String {
        let trimmedAppleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAppleID.isEmpty == false else { return "***" }

        if trimmedAppleID.contains("@") {
            return maskEmail(trimmedAppleID)
        }

        if isPhoneNumber(trimmedAppleID) {
            return maskPhone(trimmedAppleID)
        }

        return maskPlainIdentifier(trimmedAppleID)
    }

    private nonisolated static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return maskPlainIdentifier(email) }

        let localPart = parts[0]
        let domain = parts[1]
        guard localPart.isEmpty == false, domain.isEmpty == false else {
            return maskPlainIdentifier(email)
        }
        return "\(maskPlainIdentifier(localPart))@\(domain)"
    }

    private nonisolated static func maskPhone(_ value: String) -> String {
        let hasCountryPrefix = value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        let digits = String(value.filter { $0.isNumber })
        guard digits.count >= 6 else { return maskPlainIdentifier(value) }

        if hasCountryPrefix,
           let countryCodeLength = countryCodeLength(in: digits),
           digits.count > countryCodeLength {
            let countryCode = String(digits.prefix(countryCodeLength))
            let nationalNumber = String(digits.dropFirst(countryCodeLength))
            return "+\(countryCode) \(maskPhoneNationalNumber(nationalNumber))"
        }

        return maskPhoneNationalNumber(digits)
    }

    private nonisolated static func maskPhoneNationalNumber(_ digits: String) -> String {
        let characters = Array(digits)
        switch characters.count {
        case 0:
            return "***"
        case 1...5:
            return maskPlainIdentifier(digits)
        case 6...7:
            let prefix = String(characters.prefix(2))
            let suffix = String(characters.suffix(2))
            return "\(prefix)****\(suffix)"
        case 8:
            let prefix = String(characters.prefix(3))
            let suffix = String(characters.suffix(3))
            return "\(prefix)****\(suffix)"
        default:
            let prefix = String(characters.prefix(3))
            let suffix = String(characters.suffix(4))
            return "\(prefix)****\(suffix)"
        }
    }

    private nonisolated static func maskPlainIdentifier(_ identifier: String) -> String {
        let characters = Array(identifier)
        switch characters.count {
        case 0:
            return "***"
        case 1...3:
            return "\(characters[0])***"
        case 4...5:
            let prefix = String(characters.prefix(2))
            let suffix = String(characters.suffix(1))
            return "\(prefix)***\(suffix)"
        default:
            let prefix = String(characters.prefix(3))
            let suffix = String(characters.suffix(2))
            return "\(prefix)***\(suffix)"
        }
    }

    private nonisolated static func isPhoneNumber(_ value: String) -> Bool {
        let digits = value.filter { $0.isNumber }
        guard digits.count >= 6 else { return false }

        let allowedCharacters = CharacterSet(charactersIn: "+0123456789 -()")
        return value.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    private nonisolated static func countryCodeLength(in digits: String) -> Int? {
        let knownCountryCodes: Set<String> = [
            "1", "7",
            "20", "27", "30", "31", "32", "33", "34", "36", "39", "40", "41", "43", "44", "45", "46", "47", "48", "49",
            "52", "55", "60", "61", "62", "63", "64", "65", "66", "81", "82", "84", "86", "90", "91", "92", "93", "94", "95", "98",
            "212", "213", "216", "218", "234", "351", "352", "353", "354", "355", "356", "357", "358", "359",
            "370", "371", "372", "373", "374", "375", "376", "377", "380", "381", "382", "383", "385", "386", "387", "389",
            "420", "421", "852", "853", "855", "856", "886", "960", "961", "962", "963", "964", "965", "966", "967", "968",
            "971", "972", "973", "974", "975", "976", "977", "992", "993", "994", "995", "996", "998"
        ]

        for length in stride(from: min(3, digits.count - 1), through: 1, by: -1) {
            let candidate = String(digits.prefix(length))
            if knownCountryCodes.contains(candidate) {
                return length
            }
        }

        guard digits.count > 10 else { return nil }
        return min(3, max(1, digits.count - 10))
    }

    private func authenticate(
        email: String,
        password: String,
        anisetteData: ALTAnisetteData,
        verificationCode: @escaping @MainActor @Sendable () async -> String?
    ) async throws -> LegacyBox<AuthObjects> {
        try await Self.authenticateWithAPI(
            email: email,
            password: password,
            anisetteData: anisetteData,
            verificationCode: verificationCode
        )
    }

    private nonisolated static func authenticateWithAPI(
        email: String,
        password: String,
        anisetteData: ALTAnisetteData,
        verificationCode: @escaping @MainActor @Sendable () async -> String?
    ) async throws -> LegacyBox<AuthObjects> {
        try await withCheckedThrowingContinuation { continuation in
            let callback = LegacyCallbackBox(continuation)
            ALTAppleAPI.shared.authenticate(
                appleID: email,
                password: password,
                anisetteData: anisetteData,
                verificationHandler: { response in
                    let reply = VerificationReply(response)
                    Task { @MainActor in
                        reply.send(await verificationCode())
                    }
                }
            ) { account, session, error in
                if let account, let session {
                    callback.resume(
                        returning: LegacyBox(
                            AuthObjects(account: account, session: session)
                        )
                    )
                } else {
                    callback.resume(
                        throwing: error ?? URLError(.userAuthenticationRequired)
                    )
                }
            }
        }
    }

    private func fetchTeams(
        account: ALTAccount,
        session: ALTAppleAPISession
    ) async throws -> [ALTTeam] {
        try await Self.fetchTeamsWithAPI(account: account, session: session)
    }

    private nonisolated static func fetchTeamsWithAPI(
        account: ALTAccount,
        session: ALTAppleAPISession
    ) async throws -> [ALTTeam] {
        let box: LegacyBox<[ALTTeam]> = try await withCheckedThrowingContinuation {
            continuation in
            let callback = LegacyCallbackBox(continuation)
            ALTAppleAPI.shared.fetchTeams(for: account, session: session) { teams, error in
                if let teams {
                    callback.resume(returning: LegacyBox(teams))
                } else {
                    callback.resume(
                        throwing: error ?? URLError(.badServerResponse)
                    )
                }
            }
        }
        return box.value
    }

    private static func failure(from error: Error) -> ImportFailure {
        if let anisetteError = error as? AnisetteV3Error {
            let code: String
            switch anisetteError {
            case .invalidIdentifier, .invalidServerResponse:
                code = "SEAL-ANI-110"
            case .provisioningFailed:
                code = "SEAL-ANI-111"
            case .staleProvisioning:
                code = "SEAL-ANI-112"
            case .unavailable:
                code = "SEAL-ANI-113"
            }
            return ImportFailure(
                title: "无法获取设备环境",
                reason: "Anisette 服务暂时不可用",
                recovery: "重试",
                code: code
            )
        }
        let nsError = error as NSError
        let isVerificationFailure = nsError.localizedDescription
            .localizedCaseInsensitiveContains("verification")
        return ImportFailure(
            title: "无法添加账号",
            reason: isVerificationFailure ? "验证码无效" : "Apple ID 验证失败",
            recovery: "重试",
            code: isVerificationFailure ? "SEAL-AUTH-101" : "SEAL-AUTH-107"
        )
    }
}

private struct AuthObjects {
    let account: ALTAccount
    let session: ALTAppleAPISession
}

struct LegacyBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class VerificationReply: @unchecked Sendable {
    private let response: (String?) -> Void

    init(_ response: @escaping (String?) -> Void) {
        self.response = response
    }

    func send(_ code: String?) {
        response(code)
    }
}

private final class LegacyCallbackBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let pending = continuation
        continuation = nil
        return pending
    }
}
