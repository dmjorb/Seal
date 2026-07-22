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
    let options: AppSigningOptions
    let selectedCertificateSerialNumber: String?
    var allowsDroppingExtensions: Bool
    var cancellationRequested: Bool
    var status: Status

    var requestedBundleIdentifier: String? { options.requestedBundleIdentifier }

    init(
        id: UUID = UUID(),
        app: AppRecord,
        account: AppleAccountRecord,
        requestedBundleIdentifier: String? = nil,
        options: AppSigningOptions? = nil,
        selectedCertificateSerialNumber: String? = nil,
        allowsDroppingExtensions: Bool = false,
        cancellationRequested: Bool = false,
        status: Status
    ) {
        self.id = id
        self.app = app
        self.account = account
        self.options = options ?? AppSigningOptions(
            requestedBundleIdentifier: requestedBundleIdentifier,
            customization: .none,
            disposition: .signAndInstall
        )
        self.selectedCertificateSerialNumber = selectedCertificateSerialNumber
        self.allowsDroppingExtensions = allowsDroppingExtensions
        self.cancellationRequested = cancellationRequested
        self.status = status
    }
}
