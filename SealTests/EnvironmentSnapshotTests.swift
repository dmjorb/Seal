import Testing
@testable import Seal

struct EnvironmentSnapshotTests {
    @Test
    func setupStepsFollowTheSigningDependencyOrder() {
        #expect(
            EnvironmentSnapshot(
                accountCount: 0,
                verifiedAccountCount: 0,
                hasPairingFile: false,
                channelIsReady: false
            ).nextSetupStep == .account
        )
        #expect(
            EnvironmentSnapshot(
                accountCount: 1,
                verifiedAccountCount: 0,
                hasPairingFile: true,
                channelIsReady: true
            ).nextSetupStep == .account
        )
        #expect(
            EnvironmentSnapshot(
                accountCount: 1,
                verifiedAccountCount: 1,
                hasPairingFile: false,
                channelIsReady: false
            ).nextSetupStep == .pairing
        )
        #expect(
            EnvironmentSnapshot(
                accountCount: 1,
                verifiedAccountCount: 1,
                hasPairingFile: true,
                channelIsReady: false
            ).nextSetupStep == nil
        )
    }

    @Test
    func environmentConfigurationDoesNotDependOnRuntimeVPNState() {
        #expect(
            EnvironmentSnapshot(
                accountCount: 1,
                verifiedAccountCount: 1,
                hasPairingFile: true,
                channelIsReady: true
            ).isConfigured
        )
        #expect(
            EnvironmentSnapshot(
                accountCount: 1,
                verifiedAccountCount: 1,
                hasPairingFile: true,
                channelIsReady: false
            ).isConfigured
        )
    }
}
