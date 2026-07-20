import Foundation

enum ArchivePathValidator {
    static func isSafe(_ path: String) -> Bool {
        guard path.isEmpty == false,
              path.hasPrefix("/") == false,
              path.contains("\\") == false,
              path.unicodeScalars.allSatisfy({ $0.value >= 32 }) else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.isEmpty == false,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            return false
        }

        if let first = components.first,
           first.count >= 2,
           first[first.index(after: first.startIndex)] == ":" {
            return false
        }

        return true
    }
}
