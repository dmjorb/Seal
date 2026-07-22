import Foundation

protocol InstallChannel: Actor {
    func start() async throws -> String
    func stop() async
    func diagnose() async -> InstallChannelDiagnostics
    func isReady() async -> Bool
    func install(ipaData: Data, bundleID: String, isSelfReplacement: Bool) async throws
    func verifyInstalled(bundleID: String) async throws
}

extension InstallChannel {
    func withStartedChannel<Value: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: (String) async throws -> Value
    ) async throws -> Value {
        do {
            let deviceIdentifier = try await start()
            let value = try await operation(deviceIdentifier)
            await stop()
            return value
        } catch is CancellationError {
            await stop()
            throw CancellationError()
        } catch {
            await stop()
            throw error
        }
    }
}
