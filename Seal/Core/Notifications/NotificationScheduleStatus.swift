import Foundation

enum SealNotificationAuthorization: String, Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
}

struct NotificationScheduleStatus: Equatable, Sendable {
    var sealEnabled: Bool
    var authorization: SealNotificationAuthorization
    var scheduledCount: Int
    var nextReminderDate: Date?
    var schedulingFailure: String?

    static let disabled = NotificationScheduleStatus(
        sealEnabled: false,
        authorization: .notDetermined,
        scheduledCount: 0,
        nextReminderDate: nil,
        schedulingFailure: nil
    )

    var summary: String {
        if sealEnabled == false { return "Seal 内关闭" }
        if authorization == .denied { return "系统权限关闭" }
        if authorization == .notDetermined { return "系统未授权" }
        if schedulingFailure != nil { return "调度失败" }
        if scheduledCount == 0 { return "已开启 · 暂无提醒" }
        return "已安排 \(scheduledCount) 条"
    }
}
