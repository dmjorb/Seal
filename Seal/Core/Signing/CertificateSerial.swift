import Foundation

/// Canonical comparison for X.509 certificate serial numbers.
///
/// Apple/AltSign may omit a leading zero that is retained when the same serial
/// is decoded from the certificate bytes in `embedded.mobileprovision`.
/// Serial identity must therefore be compared as a hexadecimal integer rather
/// than as display text.
enum CertificateSerial {
    static func canonical(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else { return nil }

        if value.lowercased().hasPrefix("0x") {
            value.removeFirst(2)
        }

        var hex = ""
        hex.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 48...57: // 0-9
                hex.unicodeScalars.append(scalar)
            case 65...70: // A-F
                hex.unicodeScalars.append(scalar)
            case 97...102: // a-f
                hex.append(Character(String(scalar).uppercased()))
            case 9, 10, 13, 32, 45, 58: // whitespace, dash, colon
                continue
            default:
                return nil
            }
        }

        guard hex.isEmpty == false else { return nil }
        let significant = hex.drop(while: { $0 == "0" })
        return significant.isEmpty ? "0" : String(significant)
    }

    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = canonical(lhs), let rhs = canonical(rhs) else { return false }
        return lhs == rhs
    }
}
