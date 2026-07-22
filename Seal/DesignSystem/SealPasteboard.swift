import UIKit

@MainActor
enum SealPasteboard {
    static func copy(_ value: String, announcement: String = "已复制") {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}
