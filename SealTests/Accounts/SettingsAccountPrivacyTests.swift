import Testing
@testable import Seal

struct SettingsAccountPrivacyTests {
    @Test @MainActor
    func settingsViewModelDoesNotRetainFullAppleIDCache() {
        let model = SettingsViewModel.preview()
        let storedPropertyNames = Mirror(reflecting: model).children.compactMap(\.label)

        #expect(
            storedPropertyNames.contains(where: { $0.contains("fullAccountEmails") }) == false
        )
        #expect(model.accounts.allSatisfy { $0.maskedEmail.contains("***") })
    }
}
