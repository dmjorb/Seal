import Foundation

enum AppValidityTone: Equatable, Sendable {
    case success
    case neutral
    case warning
    case danger
}

struct AppValidityPresentation: Equatable, Sendable {
    let text: String
    let detailText: String
    let tone: AppValidityTone
}

enum AppValidityFormatter {
    static func presentation(expiryDate: Date?, now: Date = Date()) -> AppValidityPresentation? {
        guard let expiryDate else { return nil }
        let interval = expiryDate.timeIntervalSince(now)
        guard interval > 0 else {
            return AppValidityPresentation(text: "已过期", detailText: "已过期", tone: .danger)
        }

        if interval < 86_400 {
            let hours = max(1, Int(interval / 3_600))
            let text = "\(hours)小时"
            return AppValidityPresentation(text: text, detailText: text, tone: .danger)
        }

        let days = max(1, Int(interval / 86_400))
        let text = "\(days)天"
        return AppValidityPresentation(
            text: text,
            detailText: text,
            tone: days <= 3 ? .warning : .neutral
        )
    }

    static func text(expiryDate: Date?, now: Date = Date(), fallback: String = "—") -> String {
        presentation(expiryDate: expiryDate, now: now)?.text ?? fallback
    }
}

enum AppOperationKind: Equatable, Sendable {
    case signing
    case renewal
    case urgentRenewal
    case expiredRenewal
}

struct AppOperationPresentation: Equatable, Sendable {
    let kind: AppOperationKind
    let validity: AppValidityPresentation?

    init(app: AppRecord, now: Date = Date()) {
        guard app.state == .installed, let expiryDate = app.expiryDate else {
            kind = .signing
            validity = nil
            return
        }

        validity = AppValidityFormatter.presentation(expiryDate: expiryDate, now: now)
        guard let validity else {
            kind = .renewal
            return
        }

        switch validity.tone {
        case .danger:
            kind = expiryDate <= now ? .expiredRenewal : .urgentRenewal
        case .warning:
            kind = .urgentRenewal
        case .success, .neutral:
            kind = .renewal
        }
    }

    var sheetTitle: String {
        switch kind {
        case .signing: "签名并安装"
        case .renewal, .urgentRenewal, .expiredRenewal: "续签并安装"
        }
    }

    var primaryAction: String {
        switch kind {
        case .signing: "签名并安装"
        case .renewal, .urgentRenewal, .expiredRenewal: "续签并安装"
        }
    }
}

enum AppImportTimeFormatter {
    static func string(
        from date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time)"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "M月d日 HH:mm"
        return dateFormatter.string(from: date)
    }
}
