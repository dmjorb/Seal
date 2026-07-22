import Combine
import Foundation

@MainActor
final class VerificationCodeBroker: ObservableObject {
    @Published private(set) var isRequested = false
    @Published private(set) var hasSubmittedCode = false

    private var continuation: CheckedContinuation<String?, Never>?

    func request() async -> String? {
        cancel()
        hasSubmittedCode = false
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.isRequested = true
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel()
            }
        }
    }

    func submit(_ code: String) {
        let normalized = code.filter(\.isNumber)
        guard normalized.isEmpty == false else { return }
        hasSubmittedCode = true
        finish(with: normalized)
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with code: String?) {
        let pending = continuation
        continuation = nil
        isRequested = false
        if code == nil {
            hasSubmittedCode = false
        }
        pending?.resume(returning: code)
    }
}
