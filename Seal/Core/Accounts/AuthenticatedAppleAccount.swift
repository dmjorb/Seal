struct AuthenticatedAppleAccount: Sendable {
    let record: AppleAccountRecord
    let secret: AccountSecret
}
