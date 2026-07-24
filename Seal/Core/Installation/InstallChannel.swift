import Foundation

protocol InstallChannel: Actor {
    func start() async throws -> String
    func diagnose() async -> InstallChannelDiagnostics
    func isReady() async -> Bool
    func reset() async
    func install(ipaData: Data, bundleID: String, isSelfReplacement: Bool) async throws
    func verifyInstalled(bundleID: String) async throws
}


extension InstallChannel {
    func reset() async {}
}
