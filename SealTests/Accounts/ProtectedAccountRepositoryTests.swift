import Foundation
import Testing
@testable import Seal

struct ProtectedAccountRepositoryTests {
    @Test
    func savesUpdatesSortsAndDeletesAccounts() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appending(path: "Accounts.json")
        let repository = ProtectedAccountRepository(
            fileURL: fileURL,
            fileProtector: MarkerFileProtector()
        )
        let first = account(
            id: UUID(),
            email: "a***@icloud.com",
            verifiedAt: Date(timeIntervalSince1970: 100)
        )
        var second = account(
            id: UUID(),
            email: "b***@icloud.com",
            verifiedAt: Date(timeIntervalSince1970: 200)
        )

        try await repository.save(first)
        try await repository.save(second)
        second.status = .needsVerification
        try await repository.save(second)

        var saved = try await repository.fetchAll()
        #expect(saved.map(\.id) == [second.id, first.id])
        #expect(saved.first?.status == .needsVerification)
        #expect(FileManager.default.fileExists(
            atPath: fileURL.appendingPathExtension("protected").path
        ))

        try await repository.delete(id: second.id)
        saved = try await repository.fetchAll()
        #expect(saved == [first])
    }

    private func account(
        id: UUID,
        email: String,
        verifiedAt: Date
    ) -> AppleAccountRecord {
        AppleAccountRecord(
            id: id,
            maskedEmail: email,
            accountIdentifier: id.uuidString,
            teamID: "TEAMID",
            teamName: "Personal Team",
            lastVerifiedAt: verifiedAt
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "SealAccountTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}
