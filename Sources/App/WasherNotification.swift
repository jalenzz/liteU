import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum WasherNotification {
    static let presenter = NotificationPresenter()

    static func identifier(storeID: String) -> String {
        "washer.\(storeID)"
    }

    static func pendingStoreIDs() async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.compactMap { request in
            request.identifier.hasPrefix("washer.")
                ? String(request.identifier.dropFirst("washer.".count))
                : nil
        })
    }

    static func authorize() async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NotifyError.denied }
    }

    static func schedule(store: StoreStatus) async throws {
        guard let wait = store.waitMinutes else {
            throw NotifyError.noWait
        }
        try await authorize()
        let delay = max(WasherNotifyTiming.delaySeconds(waitMinutes: wait), 1)
        let content = UNMutableNotificationContent()
        content.title = store.name
        content.body = wait <= WasherNotifyTiming.leadMinutes
            ? "洗衣机即将空闲"
            : "大约 \(WasherNotifyTiming.leadMinutes) 分钟后可能有空闲洗衣机"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(storeID: store.id),
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    static func cancel(storeID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(storeID: storeID)]
        )
    }

    enum NotifyError: Error, LocalizedError {
        case noWait
        case denied

        var errorDescription: String? {
            switch self {
            case .noWait:
                "没有最短等待时间，无法提前提醒"
            case .denied:
                "通知未开启，请在系统设置里允许通知"
            }
        }
    }
}
