import Foundation

struct ArchiveLimits: Equatable, Sendable {
    let maximumEntryCount: Int
    let maximumExpandedSize: UInt64
    let maximumMetadataSize: UInt64
    let maximumIconSize: UInt64

    init(
        maximumEntryCount: Int = 50_000,
        maximumExpandedSize: UInt64 = 8 * 1_024 * 1_024 * 1_024,
        maximumMetadataSize: UInt64 = 2 * 1_024 * 1_024,
        maximumIconSize: UInt64 = 20 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumExpandedSize = maximumExpandedSize
        self.maximumMetadataSize = maximumMetadataSize
        self.maximumIconSize = maximumIconSize
    }
}
