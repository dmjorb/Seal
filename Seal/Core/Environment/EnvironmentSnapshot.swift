import Foundation

enum EnvironmentSetupStep: Equatable, Sendable {
    case account
    case pairing
}

struct EnvironmentSnapshot: Equatable, Sendable {
    var accountCount: Int
    var verifiedAccountCount: Int
    var hasPairingFile: Bool
    var channelIsReady: Bool

    var isConfigured: Bool {
        verifiedAccountCount > 0 && hasPairingFile
    }

    var nextSetupStep: EnvironmentSetupStep? {
        guard verifiedAccountCount > 0 else { return .account }
        guard hasPairingFile else { return .pairing }
        return nil
    }
}
