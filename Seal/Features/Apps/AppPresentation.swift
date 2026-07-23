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
        guard (app.state == .installed || app.isSeal), let expiryDate = app.expiryDate else {
            kind = .signing
            validity = nil
            return
        }

        let interval = expiryDate.timeIntervalSince(now)
        guard interval > 0 else {
            kind = .expiredRenewal
            validity = AppValidityPresentation(text: "已过期", detailText: "已过期", tone: .danger)
            return
        }

        if interval < 86_400 {
            kind = .urgentRenewal
            let hours = max(1, Int(interval / 3_600))
            validity = AppValidityPresentation(text: "\(hours)小时", detailText: "\(hours)小时", tone: .danger)
            return
        }

        let days = max(1, Int(interval / 86_400))
        kind = days <= 3 ? .urgentRenewal : .renewal
        validity = AppValidityPresentation(
            text: "\(days)天",
            detailText: "\(days)天",
            tone: days <= 3 ? .warning : .neutral
        )
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
