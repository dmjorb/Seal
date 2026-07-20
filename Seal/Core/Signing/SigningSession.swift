import Foundation

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
    var allowsDroppingExtensions: Bool
    var allowsCertificateReplacement: Bool
    var status: Status

    init(
        id: UUID = UUID(),
        app: AppRecord,
        account: AppleAccountRecord,
        requestedBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String? = nil,
        allowsDroppingExtensions: Bool = false,
        allowsCertificateReplacement: Bool = false,
        status: Status
    ) {
        self.id = id
        self.app = app
        self.account = account
        self.requestedBundleIdentifier = requestedBundleIdentifier
        self.selectedCertificateSerialNumber = selectedCertificateSerialNumber
        self.allowsDroppingExtensions = allowsDroppingExtensions
        self.allowsCertificateReplacement = allowsCertificateReplacement
        self.status = status
    }
}
