import CoreFoundation
import Foundation

enum ProvisioningEntitlementValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int64)
    case real(Double)
    case data(Data)
    case date(Date)
    case array([ProvisioningEntitlementValue])
    case dictionary([String: ProvisioningEntitlementValue])

    static func make(from value: Any) -> ProvisioningEntitlementValue? {
        if let value = value as? String { return .string(value) }
        if let value = value as? Data { return .data(value) }
        if let value = value as? Date { return .date(value) }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? Int { return .integer(Int64(value)) }
        if let value = value as? Int8 { return .integer(Int64(value)) }
        if let value = value as? Int16 { return .integer(Int64(value)) }
        if let value = value as? Int32 { return .integer(Int64(value)) }
        if let value = value as? Int64 { return .integer(value) }
        if let value = value as? UInt { return .integer(Int64(clamping: value)) }
        if let value = value as? UInt8 { return .integer(Int64(value)) }
        if let value = value as? UInt16 { return .integer(Int64(value)) }
        if let value = value as? UInt32 { return .integer(Int64(value)) }
        if let value = value as? UInt64 { return .integer(Int64(clamping: value)) }
        if let value = value as? Float { return .real(Double(value)) }
        if let value = value as? Double { return .real(value) }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            let double = value.doubleValue
            if double.rounded() == double {
                return .integer(value.int64Value)
            }
            return .real(double)
        }
        if let values = value as? [Any] {
            let converted = values.compactMap(Self.make)
            guard converted.count == values.count else { return nil }
            return .array(converted)
        }
        if let dictionary = value as? [String: Any] {
            var converted: [String: ProvisioningEntitlementValue] = [:]
            converted.reserveCapacity(dictionary.count)
            for (key, nestedValue) in dictionary {
                guard let nested = Self.make(from: nestedValue) else { return nil }
                converted[key] = nested
            }
            return .dictionary(converted)
        }
        return nil
    }

    func permits(_ requested: ProvisioningEntitlementValue) -> Bool {
        switch (self, requested) {
        case let (.string(allowed), .string(value)):
            return Self.string(allowed, permits: value)
        case let (.bool(allowed), .bool(value)):
            return allowed == value
        case let (.integer(allowed), .integer(value)):
            return allowed == value
        case let (.real(allowed), .real(value)):
            return allowed == value
        case let (.integer(allowed), .real(value)):
            return Double(allowed) == value
        case let (.real(allowed), .integer(value)):
            return allowed == Double(value)
        case let (.data(allowed), .data(value)):
            return allowed == value
        case let (.date(allowed), .date(value)):
            return allowed == value
        case let (.array(allowed), .array(values)):
            return values.allSatisfy { value in
                allowed.contains { $0.permits(value) }
            }
        case let (.dictionary(allowed), .dictionary(values)):
            return values.allSatisfy { key, value in
                guard let allowedValue = allowed[key] else { return false }
                return allowedValue.permits(value)
            }
        default:
            return false
        }
    }

    private static func string(_ allowed: String, permits requested: String) -> Bool {
        guard allowed.contains("*") else { return allowed == requested }
        let escaped = NSRegularExpression.escapedPattern(for: allowed)
            .replacingOccurrences(of: "\\*", with: ".*")
        return requested.range(
            of: "^\(escaped)$",
            options: [.regularExpression]
        ) != nil
    }
}
