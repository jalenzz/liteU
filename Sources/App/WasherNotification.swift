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
    private static let prefix = "idle."

    static func key(storeID: String, kind: MachineKind) -> String {
        "\(storeID).\(kind.rawValue)"
    }

    static func pendingKeys() async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.compactMap { request in
            request.identifier.hasPrefix(prefix) ? String(request.identifier.dropFirst(prefix.count)) : nil
        })
    }

    static func authorize() async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NotifyError.denied }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func schedule(store: StoreStatus, kind: KindStatus) async throws {
        guard let wait = kind.waitMinutes else {
            throw NotifyError.noWait
        }
        try await authorize()
        let delay = max(WasherNotifyTiming.delaySeconds(waitMinutes: wait), 1)
        let content = UNMutableNotificationContent()
        content.title = store.name
        content.body = wait <= WasherNotifyTiming.leadMinutes
            ? "\(kind.kind.title)即将空闲"
            : "大约 \(WasherNotifyTiming.leadMinutes) 分钟后可能有空闲\(kind.kind.title)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: prefix + key(storeID: store.id, kind: kind.kind),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    static func cancel(key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + key])
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

enum OrderReminder {
    private static let prefix = "order."

    /// 按当前使用中的订单重排结束提醒，已不在列表里的订单撤销提醒。未获通知授权时只撤销、不申请。
    static func sync(_ orders: [Order], authorized: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        let current = Set(orders.map { prefix + $0.id })
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) && !current.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard authorized else { return }
        for order in orders {
            guard let endsAt = order.endsAt else { continue }
            let interval = OrderReminderTiming.fireDate(endsAt: endsAt).timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = order.title
            content.body = order.storeName.isEmpty ? "还有 1 分钟结束" : "\(order.storeName) · 还有 1 分钟结束"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: prefix + order.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try await center.add(request)
        }
    }
}
