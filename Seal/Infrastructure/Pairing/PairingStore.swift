import Foundation

actor PairingStore {
    private static let maximumFileSize = 5 * 1_024 * 1_024
    private let fileURL: URL
    private let fileProtector: any FileProtecting

    init(
        fileURL: URL,
        fileProtector: any FileProtecting = CompleteFileProtector()
    ) {
        self.fileURL = fileURL
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
        guard data.count <= Self.maximumFileSize else {
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
        let isRemote = dictionary["private_key"] as? Data != nil
        let udid = (dictionary["UDID"] as? String)
            ?? (dictionary["udid"] as? String)
        guard isRemote || (udid?.isEmpty == false) else {
            throw Self.invalidFailure
        }

        let normalized = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try normalized.write(to: fileURL, options: .atomic)
        try fileProtector.protect(fileURL)
        return PairingRecord(deviceIdentifier: udid, isRemotePairing: isRemote)
    }

    func current() throws -> PairingRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let dictionary = try dictionary()
        return PairingRecord(
            deviceIdentifier: (dictionary["UDID"] as? String)
                ?? (dictionary["udid"] as? String),
            isRemotePairing: dictionary["private_key"] as? Data != nil
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

    private static let invalidFailure = ImportFailure(
        title: "配对文件无效",
        reason: "未找到设备配对信息",
        recovery: "重新导入",
        code: "SEAL-PAIR-201"
    )
}
