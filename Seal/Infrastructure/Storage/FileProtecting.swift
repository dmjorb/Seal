import Foundation

protocol FileProtecting: Sendable {
    func protect(_ url: URL) throws
}
