import Foundation
import ZIPFoundation
import UIKit

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
        customization: AppSigningCustomization = .none
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
                try archive.extract(entry, to: destination)
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
            try applyCustomization(customization, to: appURL)

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

    private func applyCustomization(
        _ customization: AppSigningCustomization,
        to appURL: URL
    ) throws {
        if let displayName = customization.normalizedDisplayName {
            try updateDisplayName(at: appURL, to: displayName)
        }
        if let iconData = customization.iconData {
            try replacePrimaryIcon(in: appURL, with: iconData)
        }
    }

    private func updateDisplayName(at appURL: URL, to displayName: String) throws {
        let infoURL = appURL.appending(path: "Info.plist")
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
        info["CFBundleDisplayName"] = displayName
        info["CFBundleName"] = displayName
        let updated = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: format,
            options: 0
        )
        try updated.write(to: infoURL, options: .atomic)
    }

    private func replacePrimaryIcon(in appURL: URL, with sourceData: Data) throws {
        guard let sourceImage = UIImage(data: sourceData) else {
            throw Self.signingFailure(reason: "所选 App 图标无法读取", code: "SEAL-SIGN-405")
        }

        let specifications: [(name: String, pixels: CGFloat)] = [
            ("SealCustomIcon20@2x.png", 40),
            ("SealCustomIcon20@3x.png", 60),
            ("SealCustomIcon29@2x.png", 58),
            ("SealCustomIcon29@3x.png", 87),
            ("SealCustomIcon40@2x.png", 80),
            ("SealCustomIcon40@3x.png", 120),
            ("SealCustomIcon60@2x.png", 120),
            ("SealCustomIcon60@3x.png", 180),
            ("SealCustomIcon76@2x.png", 152),
            ("SealCustomIcon83.5@2x.png", 167)
        ]
        for specification in specifications {
            guard let rendered = renderIcon(
                sourceImage,
                size: CGSize(width: specification.pixels, height: specification.pixels)
            ), let pngData = rendered.pngData() else {
                throw Self.signingFailure(reason: "App 图标处理失败", code: "SEAL-SIGN-405")
            }
            try pngData.write(
                to: appURL.appending(path: specification.name),
                options: .atomic
            )
        }

        let infoURL = appURL.appending(path: "Info.plist")
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

        let phoneFiles = [
            "SealCustomIcon20", "SealCustomIcon29", "SealCustomIcon40", "SealCustomIcon60"
        ]
        let padFiles = [
            "SealCustomIcon20", "SealCustomIcon29", "SealCustomIcon40",
            "SealCustomIcon76", "SealCustomIcon83.5"
        ]
        info["CFBundleIconFiles"] = phoneFiles
        info["CFBundleIcons"] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": phoneFiles,
                "UIPrerenderedIcon": false
            ]
        ]
        info["CFBundleIcons~ipad"] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": padFiles,
                "UIPrerenderedIcon": false
            ]
        ]
        info.removeValue(forKey: "CFBundleIconName")
        let updated = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: format,
            options: 0
        )
        try updated.write(to: infoURL, options: .atomic)
    }

    private func primaryIconNames(from info: [String: Any]) -> [String] {
        var values: [String] = []
        if let iconFiles = info["CFBundleIconFiles"] as? [String] {
            values.append(contentsOf: iconFiles)
        }
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primary["CFBundleIconFiles"] as? [String] {
            values.append(contentsOf: iconFiles)
        }
        if let icons = info["CFBundleIcons~ipad"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primary["CFBundleIconFiles"] as? [String] {
            values.append(contentsOf: iconFiles)
        }
        return Array(Set(values.filter { $0.isEmpty == false }))
    }

    private func iconCandidates(named name: String, in appURL: URL) -> [URL] {
        let fileManager = FileManager.default
        let baseName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()
        return (try? fileManager.contentsOfDirectory(
            at: appURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter { url in
            let candidate = url.deletingPathExtension().lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg"].contains(ext)
                && (candidate == baseName || candidate.hasPrefix(baseName + "@"))
        } ?? []
    }

    private func imageDimensions(at url: URL) -> CGSize? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image.size
    }

    private func renderIcon(_ image: UIImage, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let sourceRatio = image.size.width / max(image.size.height, 1)
            let targetRatio = size.width / max(size.height, 1)
            let drawSize: CGSize
            if sourceRatio > targetRatio {
                drawSize = CGSize(width: size.height * sourceRatio, height: size.height)
            } else {
                drawSize = CGSize(width: size.width, height: size.width / max(sourceRatio, 0.0001))
            }
            let origin = CGPoint(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
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
