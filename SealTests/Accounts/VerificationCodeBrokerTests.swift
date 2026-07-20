import Testing
@testable import Seal

@MainActor
struct VerificationCodeBrokerTests {
    @Test
    func submitCodeCompletesRequestAndMarksSubmission() async {
        let broker = VerificationCodeBroker()

        let task = Task { @MainActor in
            await broker.request()
        }
        await waitUntilRequested(broker)

        #expect(broker.isRequested)
        broker.submit("12 34 56")

        let code = await task.value
        #expect(code == "123456")
        #expect(broker.isRequested == false)
        #expect(broker.hasSubmittedCode)
    }

    @Test
    func cancelResetsPendingAndSubmittedState() async {
        let broker = VerificationCodeBroker()

        let task = Task { @MainActor in
            await broker.request()
        }
        await waitUntilRequested(broker)
        broker.cancel()

        let code = await task.value
        #expect(code == nil)
        #expect(broker.isRequested == false)
        #expect(broker.hasSubmittedCode == false)
    }

    private func waitUntilRequested(_ broker: VerificationCodeBroker) async {
        for _ in 0..<10 where broker.isRequested == false {
            await Task.yield()
        }
    }
}
