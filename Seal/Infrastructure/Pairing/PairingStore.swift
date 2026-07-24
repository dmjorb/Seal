import Foundation

actor PairingStore {
    private struct ValidationMetadata: Codable, Sendable {
        let status: PairingValidationStatus
        let validatedDeviceIdentifier: String?
        let validatedAt: Date?
    }

    private static let maximumFileSize = 5 * 1_024 * 1_024
    private let fileURL: URL
    private let metadataURL: URL
    private let backupURL: URL
    private let backupMetadataURL: URL
    private let fileProtector: any FileProtecting

    init(
        fileURL: URL,
        fileProtector: any FileProtecting = CompleteFileProtector()
    ) {
        self.fileURL = fileURL
        self.metadataURL = fileURL.appendingPathExtension("validation.json")
        self.backupURL = fileURL.appendingPathExtension("backup")
        self.backupMetadataURL = fileURL.appendingPathExtension("backup.validation.json")
        self.fileProtector = fileProtector
    }

    func importFile(at sourceURL: URL) throws -> PairingRecord {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= Self.maximumFileSize else {
            throw Self.invalidFailure
        }
        let data = try Data(contentsOf: sourceURL)
        guard data.isEmpty == false, data.count <= Self.maximumFileSize else {
            throw Self.invalidFailure
        }
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dictionary = value as? [String: Any] else {
            throw Self.invalidFailure
        }

        let inspection = try Self.inspect(dictionary)
        let normalized = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        let hadExistingPairing = FileManager.default.fileExists(atPath: fileURL.path)
        try backupCurrentIfNeeded()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try normalized.write(to: fileURL, options: .atomic)
            try fileProtector.protect(fileURL)
            try saveMetadata(
                ValidationMetadata(
                    status: .unverified,
                    validatedDeviceIdentifier: nil,
                    validatedAt: nil
                )
            )
        } catch {
            if hadExistingPairing {
                _ = try? restoreBackupIfPresent()
            } else {
                try? removeCurrentFilesAfterFailedInitialImport()
            }
            throw error
        }

        return PairingRecord(
            deviceIdentifier: inspection.udid,
            isRemotePairing: inspection.isRemote,
            validationStatus: .unverified
        )
    }

    func current() throws -> PairingRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let dictionary = try dictionary()
        let inspection = try Self.inspect(dictionary)
        let metadata = try? loadMetadata()
        let storedStatus = metadata?.status ?? .unverified
        let status: PairingValidationStatus = storedStatus == .validating ? .unverified : storedStatus
        return PairingRecord(
            deviceIdentifier: inspection.udid,
            isRemotePairing: inspection.isRemote,
            validationStatus: status,
            validatedDeviceIdentifier: metadata?.validatedDeviceIdentifier,
            validatedAt: metadata?.validatedAt
        )
    }

    func markValidated(deviceIdentifier: String) throws -> PairingRecord {
        let dictionary = try dictionary()
        let inspection = try Self.inspect(dictionary)
        if let fileUDID = inspection.udid,
           fileUDID.caseInsensitiveCompare(deviceIdentifier) != .orderedSame {
            try saveMetadata(
                ValidationMetadata(
                    status: .deviceMismatch,
                    validatedDeviceIdentifier: deviceIdentifier,
                    validatedAt: Date()
                )
            )
            throw Self.mismatchFailure(fileUDID: fileUDID, connectedUDID: deviceIdentifier)
        }

        let metadata = ValidationMetadata(
            status: .verified,
            validatedDeviceIdentifier: deviceIdentifier,
            validatedAt: Date()
        )
        try saveMetadata(metadata)
        try discardBackup()
        return PairingRecord(
            deviceIdentifier: inspection.udid,
            isRemotePairing: inspection.isRemote,
            validationStatus: .verified,
            validatedDeviceIdentifier: deviceIdentifier,
            validatedAt: metadata.validatedAt
        )
    }

    func markValidating() throws -> PairingRecord {
        try updateValidationStatus(.validating)
    }

    func markPendingValidation() throws -> PairingRecord {
        try updateValidationStatus(.unverified)
    }

    private func updateValidationStatus(
        _ status: PairingValidationStatus
    ) throws -> PairingRecord {
        let dictionary = try dictionary()
        let inspection = try Self.inspect(dictionary)
        let metadata = ValidationMetadata(
            status: status,
            validatedDeviceIdentifier: nil,
            validatedAt: nil
        )
        try saveMetadata(metadata)
        return PairingRecord(
            deviceIdentifier: inspection.udid,
            isRemotePairing: inspection.isRemote,
            validationStatus: status
        )
    }

    func contents() throws -> String {
        let data = try Data(contentsOf: fileURL)
        guard let string = String(data: data, encoding: .utf8) else {
            throw Self.invalidFailure
        }
        return string
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
        try discardBackup()
    }

    func restoreBackupIfPresent() throws -> PairingRecord? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        let data = try Data(contentsOf: backupURL)
        try data.write(to: fileURL, options: .atomic)
        try fileProtector.protect(fileURL)

        if FileManager.default.fileExists(atPath: backupMetadataURL.path) {
            let metadataData = try Data(contentsOf: backupMetadataURL)
            try metadataData.write(to: metadataURL, options: .atomic)
            try fileProtector.protect(metadataURL)
        } else if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
        try discardBackup()
        return try current()
    }

    private func backupCurrentIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              FileManager.default.fileExists(atPath: backupURL.path) == false else { return }
        let data = try Data(contentsOf: fileURL)
        try data.write(to: backupURL, options: .atomic)
        try fileProtector.protect(backupURL)
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let metadataData = try Data(contentsOf: metadataURL)
            try metadataData.write(to: backupMetadataURL, options: .atomic)
            try fileProtector.protect(backupMetadataURL)
        }
    }

    private func removeCurrentFilesAfterFailedInitialImport() throws {
        for url in [fileURL, metadataURL, backupURL, backupMetadataURL]
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func discardBackup() throws {
        for url in [backupURL, backupMetadataURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func dictionary() throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dictionary = value as? [String: Any] else {
            throw Self.invalidFailure
        }
        return dictionary
    }

    private func loadMetadata() throws -> ValidationMetadata {
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(ValidationMetadata.self, from: data)
    }

    private func saveMetadata(_ metadata: ValidationMetadata) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
        try fileProtector.protect(metadataURL)
    }

    private static func inspect(
        _ dictionary: [String: Any]
    ) throws -> (udid: String?, isRemote: Bool) {
        let udid = firstString(
            in: dictionary,
            keys: ["UDID", "udid", "UniqueDeviceID", "device_identifier"]
        )
        let hasRemotePrivateKey = containsDataOrString(
            in: dictionary,
            keys: ["private_key", "privateKey", "PrivateKey"]
        )

        // Keep RPPairing import compatible with files that were valid in
        // previous Seal builds. Static schema checks only prove that a plist
        // looks familiar; the real trust check must be done by LocalDevVPN /
        // Minimuxer against the current device.
        guard hasRemotePrivateKey || udid?.isEmpty == false else {
            throw Self.invalidFailure
        }
        return (udid, hasRemotePrivateKey)
    }

    private static func firstString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { return trimmed }
            }
        }
        return nil
    }

    private static func containsDataOrString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Bool {
        keys.contains { key in
            if let data = dictionary[key] as? Data { return data.isEmpty == false }
            if let string = dictionary[key] as? String { return string.isEmpty == false }
            return false
        }
    }

    private static let invalidFailure = ImportFailure(
        title: "配对文件无效",
        reason: "文件不是可解析的 Apple 设备配对 plist。",
        recovery: "使用 idevice_pair 重新导出",
        code: "SEAL-PAIR-201"
    )

    private static func mismatchFailure(
        fileUDID: String,
        connectedUDID: String
    ) -> ImportFailure {
        ImportFailure(
            title: "配对文件属于其他设备",
            reason: "配对文件与当前连接设备不匹配。",
            recovery: "导入当前 iPhone 的配对文件",
            code: "SEAL-PAIR-206"
        )
    }
}
