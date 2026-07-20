import Foundation
import Network

protocol VPNOnDemandActivating: Sendable {
    func activate() async
    func probeTunnel() async -> Bool
}

struct LocalDevVPNOnDemandActivator: VPNOnDemandActivating {
    private static let queue = DispatchQueue(
        label: "com.mjorb.seal.localdevvpn-on-demand",
        qos: .userInitiated
    )

    func activate() async {
        _ = await probeTunnel()
        try? await Task.sleep(for: .milliseconds(900))
    }

    func probeTunnel() async -> Bool {
        // A short TCP probe nudges iOS to bring up LocalDevVPN on demand. 62078
        // covers lockdown; 49152 covers RSD on newer device/tunnel paths.
        for endpoint in [
            ProbeEndpoint(host: "10.7.0.1", port: 62078),
            ProbeEndpoint(host: "10.7.0.1", port: 49152)
        ] {
            if await probe(endpoint, timeoutMilliseconds: 900) { return true }
        }
        return false
    }

    private func probe(_ endpoint: ProbeEndpoint, timeoutMilliseconds: Int) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port)!,
            using: .tcp
        )
        let completion = ProbeCompletion()

        return await withCheckedContinuation { continuation in
            completion.setContinuation(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    completion.resume(true)
                case .failed, .cancelled:
                    completion.resume(false)
                default:
                    break
                }
            }

            connection.start(queue: Self.queue)
            Self.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds)) {
                connection.cancel()
                completion.resume(false)
            }
        }
    }
}

private struct ProbeEndpoint: Sendable {
    let host: String
    let port: UInt16
}

private final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var didResume = false

    func setContinuation(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if didResume {
            lock.unlock()
            continuation.resume(returning: false)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ result: Bool) {
        let continuationToResume: CheckedContinuation<Bool, Never>?

        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        continuationToResume = continuation
        continuation = nil
        lock.unlock()

        continuationToResume?.resume(returning: result)
    }
}
