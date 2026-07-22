import Foundation

enum AppStoreError: Error {
    case corruptRecord
    case invalidConfiguration
    case persistence(any Error)
}
