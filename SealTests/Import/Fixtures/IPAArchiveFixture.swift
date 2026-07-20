import Foundation
import ZIPFoundation

enum IPAArchiveFixture {
    struct AppSpec {
        let directoryName: String
        let bundleIdentifier: String
        let name: String
        let version: String
        let buildNumber: String
        let malformedInfo: Bool

        init(
            directoryName: String = "Demo.app",
            bundleIdentifier: String = "com.example.demo",
            name: String = "Demo",
            version: String = "1.2.3",
            buildNumber: String = "45",
            malformedInfo: Bool = false
        ) {
            self.directoryName = directoryName
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.version = version
            self.buildNumber = buildNumber
            self.malformedInfo = malformedInfo
        }
    }

    static func make(
        apps: [AppSpec] = [AppSpec()],
        includeInfo: Bool = true,
        includeIcon: Bool = true,
        includeShareExtension: Bool = false,
        includeEntitlements: Bool = false,
        extraEntries: [(path: String, data: Data)] = []
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "SealTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archiveURL = directory.appending(path: "Fixture.ipa")
        let archive = try Archive(url: archiveURL, accessMode: .create)

        for app in apps {
            let appRoot = "Payload/\(app.directoryName)"
            if includeInfo {
                let infoData: Data
                if app.malformedInfo {
                    infoData = Data("not a property list".utf8)
                } else {
                    infoData = try propertyListData([
                        "CFBundleDisplayName": app.name,
                        "CFBundleIdentifier": app.bundleIdentifier,
                        "CFBundleShortVersionString": app.version,
                        "CFBundleVersion": app.buildNumber,
                        "CFBundleIcons": [
                            "CFBundlePrimaryIcon": [
                                "CFBundleIconFiles": ["AppIcon60x60"]
                            ]
                        ]
                    ])
                }
                try add(infoData, path: "\(appRoot)/Info.plist", to: archive)
            }

            if includeIcon {
                try add(Data("fixture-icon".utf8), path: "\(appRoot)/AppIcon60x60@3x.png", to: archive)
            }

            if includeEntitlements {
                let entitlements = try propertyListData([
                    "aps-environment": "development",
                    "com.apple.security.application-groups": ["group.example.demo"]
                ])
                try add(entitlements, path: "\(appRoot)/archived-expanded-entitlements.xcent", to: archive)
            }

            if includeShareExtension {
                let extensionInfo = try propertyListData([
                    "CFBundleDisplayName": "Share",
                    "CFBundleIdentifier": "\(app.bundleIdentifier).share",
                    "NSExtension": [
                        "NSExtensionPointIdentifier": "com.apple.share-services"
                    ]
                ])
                try add(
                    extensionInfo,
                    path: "\(appRoot)/PlugIns/Share.appex/Info.plist",
                    to: archive
                )
            }
        }

        for entry in extraEntries {
            try add(entry.data, path: entry.path, to: archive)
        }

        return archiveURL
    }

    private static func propertyListData(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        )
    }

    private static func add(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            return data.subdata(in: start..<(start + size))
        }
    }
}
