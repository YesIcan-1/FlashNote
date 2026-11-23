import Foundation

#if os(macOS)
import UserNotifications

/// Mac 系统通知只发送任务的开始、完成或失败；中间进度留在应用界面。
final class AppNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationService()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func post(_ notice: WorkflowNotice) {
        Task {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                await requestAuthorization()
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: notice.kind)
            content.body = Self.body(for: notice)
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private static func title(for kind: WorkflowNoticeKind) -> String {
        switch kind {
        case .downloadStarted: "开始下载"
        case .downloadCompleted: "下载完成"
        case .downloadFailed: "下载失败"
        case .transcriptionStarted: "开始转写"
        case .transcriptionCompleted: "转写完成"
        case .transcriptionFailed: "转写失败"
        case .minutesStarted: "开始生成会议纪要"
        case .minutesCompleted: "会议纪要已生成"
        case .minutesFailed: "会议纪要生成失败"
        }
    }

    private static func body(for notice: WorkflowNotice) -> String {
        if let detail = notice.detail, !detail.isEmpty { return "\(notice.title)：\(detail)" }
        return notice.title
    }
}
#else
final class AppNotificationService {
    static let shared = AppNotificationService()
    func requestAuthorization() async {}
    func post(_ notice: WorkflowNotice) {}
}
#endif
