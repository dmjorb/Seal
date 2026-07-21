import Foundation
import ZIPFoundation

struct IPAParserService: Sendable {
    let limits: ArchiveLimits

    init(limits: ArchiveLimits = ArchiveLimits()) {
        self.limits = limits
    }

    func parse(url: URL) throws -> ParsedIPA {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw failure(
                title: "无法打开 IPA",
                reason: "文件不是有效的 IPA",
                recovery: "选择其他 IPA",
                code: "SEAL-IPA-106"
            )
        }

        do {
            return try parse(archive: archive, sourceURL: url)
        } catch let error as ImportFailure {
            throw error
        } catch {
            throw failure(
                title: "无法读取 IPA",
                reason: "应用信息已损坏",
                recovery: "选择其他 IPA",
                code: "SEAL-IPA-102"
            )
        }
    }

    private func parse(archive: Archive, sourceURL: URL) throws -> ParsedIPA {
        let entries = Array(archive)
        try validate(entries: entries)

        let appInfoEntries = entries.filter { entry in
            let components = entry.path.split(separator: "/")
            return components.count == 3
                && components[0] == "Payload"
                && components[1].hasSuffix(".app")
                && components[2] == "Info.plist"
        }

        guard appInfoEntries.isEmpty == false else {
            throw failure(
                title: "无法读取 IPA",
                reason: "未找到应用信息",
                recovery: "选择其他 IPA",
                code: "SEAL-IPA-101"
            )
        }
        guard appInfoEntries.count == 1, let appInfoEntry = appInfoEntries.first else {
            throw failure(
                title: "无法读取 IPA",
                reason: "包含多个主应用",
                recovery: "选择标准 IPA",
                code: "SEAL-IPA-103"
            )
        }

        let info = try propertyList(
            from: appInfoEntry,
            in: archive,
            maximumSize: limits.maximumMetadataSize
        )
        guard let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              bundleIdentifier.isEmpty == false,
              let version = info["CFBundleShortVersionString"] as? String,
              version.isEmpty == false,
              let buildNumber = info["CFBundleVersion"] as? String,
              buildNumber.isEmpty == false,
              let name = displayName(from: info),
              name.isEmpty == false else {
            throw failure(
                title: "无法读取 IPA",
                reason: "应用信息不完整",
                recovery: "选择其他 IPA",
                code: "SEAL-IPA-102"
            )
        }

        let appRoot = appInfoEntry.path
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        let iconData = try readIcon(
            info: info,
            appRoot: appRoot,
            entries: entries,
            archive: archive
        )
        let appExtensions = try readExtensions(
            appRoot: appRoot,
            entries: entries,
            archive: archive
        )
        let entitlementKeys = readEntitlementKeys(
            appRoot: appRoot,
            entries: entries,
            archive: archive
        )
        let fileSize = try sourceFileSize(at: sourceURL)

        return ParsedIPA(
            name: name,
            bundleIdentifier: bundleIdentifier,
            version: version,
            buildNumber: buildNumber,
            fileSize: fileSize,
            iconData: iconData,
            extensions: appExtensions,
            entitlementKeys: entitlementKeys
        )
    }

    private func validate(entries: [Entry]) throws {
        guard entries.count <= limits.maximumEntryCount else {
            throw sizeFailure()
        }

        var expandedSize: UInt64 = 0
        for entry in entries {
            guard ArchivePathValidator.isSafe(entry.path) else {
                throw failure(
                    title: "IPA 不安全",
                    reason: "压缩包包含非法路径",
                    recovery: "选择其他 IPA",
                    code: "SEAL-IPA-104"
                )
            }

            let (sum, overflow) = expandedSize.addingReportingOverflow(entry.uncompressedSize)
            guard overflow == false, sum <= limits.maximumExpandedSize else {
                throw sizeFailure()
            }
            expandedSize = sum
        }
    }

    private func propertyList(
        from entry: Entry,
        in archive: Archive,
        maximumSize: UInt64
    ) throws -> [String: Any] {
        let data = try data(from: entry, in: archive, maximumSize: maximumSize)
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dictionary = value as? [String: Any] else {
            throw failure(
                title: "无法读取 IPA",
                reason: "应用信息已损坏",
                recovery: "选择其他 IPA",
                code: "SEAL-IPA-102"
            )
        }
        return dictionary
    }

    private func data(
        from entry: Entry,
        in archive: Archive,
        maximumSize: UInt64
    ) throws -> Data {
        guard entry.uncompressedSize <= maximumSize else {
            throw sizeFailure()
        }

        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        try archive.extract(entry) { chunk in
            result.append(chunk)
        }
        return result
    }

    private func displayName(from info: [String: Any]) -> String? {
        (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
    }

    private func readIcon(
        info: [String: Any],
        appRoot: String,
        entries: [Entry],
        archive: Archive
    ) throws -> Data? {
        let iconNames = iconFileNames(from: info)
        let pngEntries = entries.filter { entry in
            entry.type == .file
                && entry.path.hasPrefix("\(appRoot)/")
                && entry.path.lowercased().hasSuffix(".png")
        }

        let declared = pngEntries.filter { entry in
            let fileName = URL(filePath: entry.path).deletingPathExtension().lastPathComponent
            return iconNames.contains { declaredName in
                fileName.caseInsensitiveCompare(declaredName) == .orderedSame
                    || fileName.localizedCaseInsensitiveContains(declaredName)
                    || fileName.hasPrefix(declaredName)
            }
        }

        let fallbacks = pngEntries.filter { entry in
            let lower = URL(filePath: entry.path).lastPathComponent.lowercased()
            return lower.hasPrefix("icon")
                || lower.hasPrefix("appicon")
                || lower.contains("appicon")
                || lower.contains("itunesartwork")
        }

        guard let selected = (declared + fallbacks).max(by: {
            $0.uncompressedSize < $1.uncompressedSize
        }) else {
            return nil
        }

        return try data(
            from: selected,
            in: archive,
            maximumSize: limits.maximumIconSize
        )
    }

    private func iconFileNames(from info: [String: Any]) -> [String] {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        if let files = info["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private func readExtensions(
        appRoot: String,
        entries: [Entry],
        archive: Archive
    ) throws -> [AppExtensionRecord] {
        let infoEntries = entries.filter { entry in
            entry.path.hasPrefix("\(appRoot)/PlugIns/")
                && entry.path.hasSuffix(".appex/Info.plist")
        }

        return try infoEntries.map { entry in
            let info = try propertyList(
                from: entry,
                in: archive,
                maximumSize: limits.maximumMetadataSize
            )
            guard let bundleIdentifier = info["CFBundleIdentifier"] as? String,
                  bundleIdentifier.isEmpty == false else {
                throw failure(
                    title: "无法读取 IPA",
                    reason: "扩展信息已损坏",
                    recovery: "选择其他 IPA",
                    code: "SEAL-IPA-102"
                )
            }
            let name = displayName(from: info)
                ?? URL(filePath: entry.path).deletingLastPathComponent().lastPathComponent
            let extensionInfo = info["NSExtension"] as? [String: Any]
            let pointIdentifier = extensionInfo?["NSExtensionPointIdentifier"] as? String

            return AppExtensionRecord(
                name: name,
                originalBundleIdentifier: bundleIdentifier,
                kind: extensionKind(for: pointIdentifier)
            )
        }
    }

    private func extensionKind(for pointIdentifier: String?) -> AppExtensionKind {
        switch pointIdentifier {
        case "com.apple.share-services":
            return .share
        case "com.apple.usernotifications.service":
            return .notificationService
        case "com.apple.widgetkit-extension", "com.apple.widget-extension":
            return .widget
        default:
            return .unknown
        }
    }

    private func readEntitlementKeys(
        appRoot: String,
        entries: [Entry],
        archive: Archive
    ) -> Set<String> {
        let entitlementEntries = entries.filter { entry in
            entry.path.hasPrefix("\(appRoot)/")
                && entry.path.hasSuffix(".xcent")
                && entry.uncompressedSize <= limits.maximumMetadataSize
        }

        return entitlementEntries.reduce(into: Set<String>()) { keys, entry in
            guard let info = try? propertyList(
                from: entry,
                in: archive,
                maximumSize: limits.maximumMetadataSize
            ) else {
                return
            }
            keys.formUnion(info.keys)
        }
    }

    private func sourceFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber else { return 0 }
        return number.int64Value
    }

    private func sizeFailure() -> ImportFailure {
        failure(
            title: "IPA 过大",
            reason: "解压内容超过安全上限",
            recovery: "选择较小的 IPA",
            code: "SEAL-IPA-105"
        )
    }

    private func failure(
        title: String,
        reason: String,
        recovery: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(
            title: title,
            reason: reason,
            recovery: recovery,
            code: code
        )
    }
}
