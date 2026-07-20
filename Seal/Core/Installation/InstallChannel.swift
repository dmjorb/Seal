import Foundation

protocol InstallChannel: Actor {
    func start() async throws -> String
    func diagnose() async -> InstallChannelDiagnostics
    func isReady() async -> Bool
    func install(ipaData: Data, bundleID: String) async throws
    func verifyInstalled(bundleID: String) async throws
}
