import Foundation

enum SigningCompletionMode: String, Equatable, Sendable {
    case signAndInstall
    case signOnly
}

struct SigningSession: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case running(SigningStage)
        case succeeded(AppRecord)
        case failed(ImportFailure)
    }

    let id: UUID
    let app: AppRecord
    let account: AppleAccountRecord
    let requestedBundleIdentifier: String?
    let selectedCertificateSerialNumber: String?
    let completionMode: SigningCompletionMode
    var allowsDroppingExtensions: Bool
    var status: Status

    init(
        id: UUID = UUID(),
        app: AppRecord,
        account: AppleAccountRecord,
        requestedBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String? = nil,
        completionMode: SigningCompletionMode = .signAndInstall,
        allowsDroppingExtensions: Bool = false,
        status: Status
    ) {
        self.id = id
        self.app = app
        self.account = account
        self.requestedBundleIdentifier = requestedBundleIdentifier
        self.selectedCertificateSerialNumber = selectedCertificateSerialNumber
        self.completionMode = completionMode
        self.allowsDroppingExtensions = allowsDroppingExtensions
        self.status = status
    }
}
