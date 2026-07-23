import Foundation

struct X509CertificateValidity: Equatable, Sendable {
    let notBefore: Date
    let notAfter: Date

    func isExpired(at date: Date = Date()) -> Bool {
        notAfter <= date
    }
}

enum X509CertificateValidityReader {
    private struct Node {
        let tag: UInt8
        let contentRange: Range<Int>
        let fullRange: Range<Int>
    }

    static func validity(from certificateData: Data) -> X509CertificateValidity? {
        guard let der = normalizedDER(from: certificateData) else { return nil }
        let bytes = [UInt8](der)
        guard let root = node(in: bytes, at: 0), root.tag == 0x30,
              let tbs = children(of: root, in: bytes).first,
              tbs.tag == 0x30 else {
            return nil
        }

        let tbsChildren = children(of: tbs, in: bytes)
        let offset = tbsChildren.first?.tag == 0xA0 ? 1 : 0
        // TBSCertificate: [version], serial, signature, issuer, validity, ...
        let validityIndex = offset + 3
        guard tbsChildren.indices.contains(validityIndex) else { return nil }
        let validityNode = tbsChildren[validityIndex]
        guard validityNode.tag == 0x30 else { return nil }

        let validityChildren = children(of: validityNode, in: bytes)
        guard validityChildren.count >= 2,
              let notBefore = date(from: validityChildren[0], bytes: bytes),
              let notAfter = date(from: validityChildren[1], bytes: bytes) else {
            return nil
        }
        return X509CertificateValidity(notBefore: notBefore, notAfter: notAfter)
    }

    private static func normalizedDER(from data: Data) -> Data? {
        guard data.isEmpty == false else { return nil }
        if data.first == 0x30 { return data }
        guard let text = String(data: data, encoding: .utf8),
              text.contains("-----BEGIN CERTIFICATE-----") else {
            return nil
        }
        let base64 = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                line.isEmpty == false
                    && line.hasPrefix("-----BEGIN CERTIFICATE-----") == false
                    && line.hasPrefix("-----END CERTIFICATE-----") == false
            }
            .joined()
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    private static func children(of parent: Node, in bytes: [UInt8]) -> [Node] {
        var result: [Node] = []
        var cursor = parent.contentRange.lowerBound
        while cursor < parent.contentRange.upperBound {
            guard let child = node(in: bytes, at: cursor),
                  child.fullRange.upperBound <= parent.contentRange.upperBound,
                  child.fullRange.upperBound > cursor else {
                return []
            }
            result.append(child)
            cursor = child.fullRange.upperBound
        }
        return cursor == parent.contentRange.upperBound ? result : []
    }

    private static func node(in bytes: [UInt8], at offset: Int) -> Node? {
        guard bytes.indices.contains(offset), bytes.indices.contains(offset + 1) else { return nil }
        let tag = bytes[offset]
        let firstLengthByte = bytes[offset + 1]
        let contentLength: Int
        let headerLength: Int

        if firstLengthByte & 0x80 == 0 {
            contentLength = Int(firstLengthByte)
            headerLength = 2
        } else {
            let lengthByteCount = Int(firstLengthByte & 0x7F)
            guard lengthByteCount > 0, lengthByteCount <= MemoryLayout<Int>.size,
                  offset + 1 + lengthByteCount < bytes.count else {
                return nil
            }
            var length = 0
            for index in 0..<lengthByteCount {
                let byte = Int(bytes[offset + 2 + index])
                guard length <= (Int.max - byte) / 256 else { return nil }
                length = length * 256 + byte
            }
            contentLength = length
            headerLength = 2 + lengthByteCount
        }

        let contentStart = offset + headerLength
        guard contentLength >= 0, contentStart <= bytes.count,
              contentLength <= bytes.count - contentStart else {
            return nil
        }
        let end = contentStart + contentLength
        return Node(
            tag: tag,
            contentRange: contentStart..<end,
            fullRange: offset..<end
        )
    }

    private static func date(from node: Node, bytes: [UInt8]) -> Date? {
        guard node.tag == 0x17 || node.tag == 0x18,
              let value = String(
                bytes: bytes[node.contentRange],
                encoding: .ascii
              ) else {
            return nil
        }
        return node.tag == 0x17
            ? utcTime(value)
            : generalizedTime(value)
    }

    private static func utcTime(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else { return nil }
        let digits = String(value.dropLast())
        guard digits.count == 10 || digits.count == 12,
              let year2 = integer(digits, 0, 2),
              let month = integer(digits, 2, 2),
              let day = integer(digits, 4, 2),
              let hour = integer(digits, 6, 2),
              let minute = integer(digits, 8, 2) else {
            return nil
        }
        let second = digits.count == 12 ? integer(digits, 10, 2) : 0
        guard let second else { return nil }
        let year = year2 >= 50 ? 1900 + year2 : 2000 + year2
        return makeDate(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    }

    private static func generalizedTime(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else { return nil }
        let digits = String(value.dropLast())
        guard digits.count == 12 || digits.count == 14,
              let year = integer(digits, 0, 4),
              let month = integer(digits, 4, 2),
              let day = integer(digits, 6, 2),
              let hour = integer(digits, 8, 2),
              let minute = integer(digits, 10, 2) else {
            return nil
        }
        let second = digits.count == 14 ? integer(digits, 12, 2) : 0
        guard let second else { return nil }
        return makeDate(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    }

    private static func integer(_ text: String, _ start: Int, _ length: Int) -> Int? {
        guard start >= 0, length > 0, start + length <= text.count else { return nil }
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(lower, offsetBy: length)
        return Int(text[lower..<upper])
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }
}
