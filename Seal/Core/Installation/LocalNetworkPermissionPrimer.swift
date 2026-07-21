import Foundation
import Network

/// Triggers iOS local-network permission before notification permission.
/// It only performs a short probe and never opens or selects VPN.
enum LocalNetworkPermissionPrimer {
    static func requestIfNeeded() async {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host("10.7.0.1"),
                port: NWEndpoint.Port(integerLiteral: 62078),
                using: .tcp
            )
            let queue = DispatchQueue(label: "com.mjorb.seal.local-network-permission")
            let probe = LocalNetworkPermissionProbe(
                connection: connection,
                continuation: continuation
            )
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    probe.finish()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 0.8) {
                probe.finish()
            }
        }
    }
}

private final class LocalNetworkPermissionProbe: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Void, Never>
    private let lock = NSLock()
    private var isFinished = false

    init(connection: NWConnection, continuation: CheckedContinuation<Void, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish() {
        lock.lock()
        let shouldFinish = isFinished == false
        if shouldFinish { isFinished = true }
        lock.unlock()
        guard shouldFinish else { return }
        connection.cancel()
        continuation.resume()
    }
}
