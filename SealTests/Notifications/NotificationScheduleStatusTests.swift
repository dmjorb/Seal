import Foundation
import Testing
@testable import Seal

struct NotificationScheduleStatusTests {
    @Test
    func summaryDistinguishesSealAndSystemStates() {
        #expect(NotificationScheduleStatus.disabled.summary == "Seal 内关闭")
        #expect(NotificationScheduleStatus(
            sealEnabled: true,
            authorization: .notDetermined,
            scheduledCount: 0,
            nextReminderDate: nil,
            schedulingFailure: nil
        ).summary == "系统未授权")
        #expect(NotificationScheduleStatus(
            sealEnabled: true,
            authorization: .denied,
            scheduledCount: 0,
            nextReminderDate: nil,
            schedulingFailure: nil
        ).summary == "系统权限关闭")
        #expect(NotificationScheduleStatus(
            sealEnabled: true,
            authorization: .allowed,
            scheduledCount: 0,
            nextReminderDate: nil,
            schedulingFailure: "failed"
        ).summary == "调度失败")
        #expect(NotificationScheduleStatus(
            sealEnabled: true,
            authorization: .allowed,
            scheduledCount: 3,
            nextReminderDate: Date(timeIntervalSince1970: 1_800_000_000),
            schedulingFailure: nil
        ).summary == "已安排 3 条")
    }
}
