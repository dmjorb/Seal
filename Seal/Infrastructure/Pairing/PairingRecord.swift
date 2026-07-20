import Foundation

struct PairingRecord: Equatable, Sendable {
    let deviceIdentifier: String?
    let isRemotePairing: Bool
}
