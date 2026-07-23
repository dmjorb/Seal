import Foundation
import UIKit
import ZIPFoundation

struct SigningWorkspace: Sendable {
    let limits: ArchiveLimits
    let bundleIDMapper: BundleIDMapper

    init(
        limits: ArchiveLimits = ArchiveLimits(),
        bundleIDMapper: BundleIDMapper = BundleIDMapper()
    ) {
        self.limits = limits
        self.bundleIDMapper = bundleIDMapper
    }

    func prepare(
        ipaURL: URL,
        workspaceRoot: URL,
        originalBundleID: String,
        teamID: String,
        targetMainBundleID: String? = nil,
        preferredDisplayName: String? = nil,
        preferredIconData: Data? = nil
    ) throws -> PreparedSigningWorkspace {
        let archive = try Archive(url: ipaURL, accessMode: .read)
        let entries = Array(archive)
        try validate(entries)

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: workspaceRoot)
        try fileManager.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )
        do {
            for entry in entries {
                try Task.checkCancellation()
                let destination = workspaceRoot.appending(path: entry.path)
                _ = try archive.extract(entry, to: destination)
            }

            let payloadURL = workspaceRoot.appending(
                path: "Payload",
                directoryHint: .isDirectory
            )
            let appURLs = try fileManager.contentsOfDirectory(
                at: payloadURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "app" }
            guard appURLs.count == 1, let appURL = appURLs.first else {
                throw Self.signingFailure(
                    reason: "未找到主应用",
                    code: "SEAL-SIGN-401"
                )
            }

            let mappedMain = bundleIDMapper.mainBundleID(
                original: originalBundleID,
                teamID: teamID,
                requested: targetMainBundleID
            )
            var mappings = [originalBundleID: mappedMain]
            try updateBundleIdentifier(at: appURL, to: mappedMain)
            if let preferredDisplayName = normalizedDisplayName(preferredDisplayName) {
                try updateDisplayName(at: appURL, to: preferredDisplayName)
            }
            if let preferredIconData {
                try replacePrimaryAppIcon(at: appURL, imageData: preferredIconData)
            }

            let extensionURLs = try appExtensionURLs(in: appURL)
            for extensionURL in extensionURLs {
                try Task.checkCancellation()
                let original = try bundleIdentifier(at: extensionURL)
                let mapped = bundleIDMapper.extensionBundleID(
                    original: original,
                    originalMainBundleID: originalBundleID,
                    mappedMainBundleID: mappedMain
                )
                try updateBundleIdentifier(at: extensionURL, to: mapped)
                mappings[original] = mapped
            }
            try removeOldSignatures(in: appURL)

            return PreparedSigningWorkspace(
                rootURL: workspaceRoot,
                payloadURL: payloadURL,
                appURL: appURL,
                mappedMainBundleID: mappedMain,
                bundleIDMappings: mappings
            )
        } catch {
            try? fileManager.removeItem(at: workspaceRoot)
            throw error
        }
    }

    func package(
        _ workspace: PreparedSigningWorkspace,
        outputURL: URL
    ) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: outputURL)
        try fileManager.zipItem(
            at: workspace.payloadURL,
            to: outputURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )
    }

    func clean(_ workspace: PreparedSigningWorkspace) {
        try? FileManager.default.removeItem(at: workspace.rootURL)
    }


    func signedBundleTargets(in workspace: PreparedSigningWorkspace) throws -> [SignedBundleTarget] {
        var targets = [
            SignedBundleTarget(
                bundleURL: workspace.appURL,
                bundleIdentifier: try bundleIdentifier(at: workspace.appURL),
                isMainApplication: true
            )
        ]
        for extensionURL in try appExtensionURLs(in: workspace.appURL) {
            targets.append(
                SignedBundleTarget(
                    bundleURL: extensionURL,
                    bundleIdentifier: try bundleIdentifier(at: extensionURL),
                    isMainApplication: false
                )
            )
        }
        return targets
    }

    func removeExtension(
        mappedBundleIdentifier: String,
        from workspace: PreparedSigningWorkspace
    ) throws {
        for extensionURL in try appExtensionURLs(in: workspace.appURL) {
            if try bundleIdentifier(at: extensionURL) == mappedBundleIdentifier {
                try FileManager.default.removeItem(at: extensionURL)
                return
            }
        }
    }

    private func validate(_ entries: [Entry]) throws {
        guard entries.count <= limits.maximumEntryCount else {
            throw Self.signingFailure(
                reason: "解压内容超过安全上限",
                code: "SEAL-SIGN-402"
            )
        }
        var expandedSize: UInt64 = 0
        for entry in entries {
            guard ArchivePathValidator.isSafe(entry.path), entry.type != .symlink else {
                throw Self.signingFailure(
                    reason: "IPA 包含不安全路径",
                    code: "SEAL-SIGN-403"
                )
            }
            let (sum, overflow) = expandedSize.addingReportingOverflow(entry.uncompressedSize)
            guard overflow == false, sum <= limits.maximumExpandedSize else {
                throw Self.signingFailure(
                    reason: "解压内容超过安全上限",
                    code: "SEAL-SIGN-402"
                )
            }
            expandedSize = sum
        }
    }

    private func appExtensionURLs(in appURL: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var values: [URL] = []
        for case let url as URL in enumerator {
            let resourceValues = try url.resourceValues(forKeys: Set(keys))
            if resourceValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard resourceValues.isDirectory == true else { continue }
            if url.pathExtension.lowercased() == "appex" {
                values.append(url)
                enumerator.skipDescendants()
            }
        }
        return values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func bundleIdentifier(at bundleURL: URL) throws -> String {
        let infoURL = bundleURL.appending(path: "Info.plist")
        let data = try Data(contentsOf: infoURL)
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let info = value as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String,
              identifier.isEmpty == false else {
            throw Self.signingFailure(
                reason: "应用标识无效",
                code: "SEAL-SIGN-404"
            )
        }
        return identifier
    }

    private func updateBundleIdentifier(
        at bundleURL: URL,
        to identifier: String
    ) throws {
        let infoURL = bundleURL.appending(path: "Info.plist")
        let data = try Data(contentsOf: infoURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: &format
        )
        guard var info = value as? [String: Any] else {
            throw Self.signingFailure(
                reason: "应用信息无效",
                code: "SEAL-SIGN-404"
            )
        }
        info["CFBundleIdentifier"] = identifier
        info.removeValue(forKey: "DTXcode")
        info.removeValue(forKey: "DTXcodeBuild")
        let updated = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: format,
            options: 0
        )
        try updated.write(to: infoURL, options: .atomic)
    }

    private func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateDisplayName(at appURL: URL, to displayName: String) throws {
        try mutateInfoPlist(at: appURL.appending(path: "Info.plist")) { info in
            info["CFBundleDisplayName"] = displayName
            info["CFBundleName"] = displayName
        }

        let localizationURLs = (try? FileManager.default.contentsOfDirectory(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for localizationURL in localizationURLs where localizationURL.pathExtension == "lproj" {
            let stringsURL = localizationURL.appending(path: "InfoPlist.strings")
            guard FileManager.default.fileExists(atPath: stringsURL.path) else { continue }
            do {
                let data = try Data(contentsOf: stringsURL)
                var format = PropertyListSerialization.PropertyListFormat.openStep
                let value = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [.mutableContainersAndLeaves],
                    format: &format
                )
                guard var strings = value as? [String: Any] else { continue }
                strings["CFBundleDisplayName"] = displayName
                strings["CFBundleName"] = displayName
                let updated = try PropertyListSerialization.data(
                    fromPropertyList: strings,
                    format: format,
                    options: 0
                )
                try updated.write(to: stringsURL, options: .atomic)
            } catch {
                // A malformed optional localization must not corrupt the IPA.
                continue
            }
        }
    }

    private func replacePrimaryAppIcon(at appURL: URL, imageData: Data) throws {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else {
            throw Self.signingFailure(reason: "自定义 App 图标无法读取", code: "SEAL-CUSTOM-004")
        }

        let variants: [(name: String, pixels: CGFloat)] = [
            ("SealCustomIcon60@2x.png", 120),
            ("SealCustomIcon60@3x.png", 180),
            ("SealCustomIcon76@2x.png", 152),
            ("SealCustomIcon83.5@2x.png", 167)
        ]
        for variant in variants {
            let rendered = try renderedSquareIcon(image, pixels: variant.pixels)
            try rendered.write(to: appURL.appending(path: variant.name), options: .atomic)
        }

        try mutateInfoPlist(at: appURL.appending(path: "Info.plist")) { info in
            var phoneIcons = (info["CFBundleIcons"] as? [String: Any]) ?? [:]
            var phonePrimary = (phoneIcons["CFBundlePrimaryIcon"] as? [String: Any]) ?? [:]
            phonePrimary["CFBundleIconFiles"] = ["SealCustomIcon60"]
            phonePrimary.removeValue(forKey: "CFBundleIconName")
            phoneIcons["CFBundlePrimaryIcon"] = phonePrimary
            info["CFBundleIcons"] = phoneIcons

            var padIcons = (info["CFBundleIcons~ipad"] as? [String: Any]) ?? [:]
            var padPrimary = (padIcons["CFBundlePrimaryIcon"] as? [String: Any]) ?? [:]
            padPrimary["CFBundleIconFiles"] = ["SealCustomIcon76", "SealCustomIcon83.5"]
            padPrimary.removeValue(forKey: "CFBundleIconName")
            padIcons["CFBundlePrimaryIcon"] = padPrimary
            info["CFBundleIcons~ipad"] = padIcons
            info["CFBundleIconFiles"] = ["SealCustomIcon60", "SealCustomIcon76"]
            info.removeValue(forKey: "CFBundleIconName")
        }
    }

    private func renderedSquareIcon(_ image: UIImage, pixels: CGFloat) throws -> Data {
        guard let source = image.cgImage else {
            throw Self.signingFailure(reason: "自定义 App 图标无法处理", code: "SEAL-CUSTOM-004")
        }
        let side = min(source.width, source.height)
        let sourceRect = CGRect(
            x: (source.width - side) / 2,
            y: (source.height - side) / 2,
            width: side,
            height: side
        )
        guard let cgImage = source.cropping(to: sourceRect) else {
            throw Self.signingFailure(reason: "自定义 App 图标无法处理", code: "SEAL-CUSTOM-004")
        }
        let cropped = UIImage(cgImage: cgImage, scale: 1, orientation: image.imageOrientation)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)
        let output = renderer.image { _ in
            cropped.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        guard let png = output.pngData() else {
            throw Self.signingFailure(reason: "自定义 App 图标无法编码", code: "SEAL-CUSTOM-004")
        }
        return png
    }

    private func mutateInfoPlist(
        at infoURL: URL,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        let data = try Data(contentsOf: infoURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: &format
        )
        guard var info = value as? [String: Any] else {
            throw Self.signingFailure(reason: "应用信息无效", code: "SEAL-SIGN-404")
        }
        mutation(&info)
        let updated = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: format,
            options: 0
        )
        try updated.write(to: infoURL, options: .atomic)
    }

    private func removeOldSignatures(in appURL: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }
        var signatureDirectories: [URL] = []
        for case let url as URL in enumerator
        where url.lastPathComponent == "_CodeSignature" {
            signatureDirectories.append(url)
            enumerator.skipDescendants()
        }
        for directory in signatureDirectories {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func signingFailure(
        reason: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(
            title: "无法签名",
            reason: reason,
            recovery: "检查 IPA",
            code: code
        )
    }
}
