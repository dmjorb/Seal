import Foundation
@testable import Seal

struct MarkerFileProtector: FileProtecting {
    func protect(_ url: URL) throws {
        guard url.hasDirectoryPath == false else { return }
        try Data().write(to: url.appendingPathExtension("protected"))
    }
}
