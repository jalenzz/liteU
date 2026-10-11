import ActivityKit
import BackgroundTasks
import Foundation

@MainActor
enum OrderActivity {
    static let refreshTaskID = "com.liteu.app.refresh-orders"

    /// 有结束时刻的使用中订单开启或更新实时活动，其余订单的实时活动立即结束。无推送，只在 App 拉到订单时同步。
    static func sync(_ orders: [Order]) async {
        let endsAt = Dictionary(uniqueKeysWithValues: orders.compactMap { order in order.endsAt.map { (order.id, $0) } })
        for activity in Activity<OrderActivityAttributes>.activities {
            if let date = endsAt[activity.attributes.orderID] {
                await activity.update(content(endsAt: date))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        let existing = Set(Activity<OrderActivityAttributes>.activities.map(\.attributes.orderID))
        for order in orders where !existing.contains(order.id) {
            guard let date = order.endsAt else { continue }
            let attributes = OrderActivityAttributes(
                orderID: order.id,
                title: order.title,
                storeName: order.storeName,
                kind: MachineKind(typeName: order.machineName)
            )
            // 用户在系统设置里关闭实时活动时会失败，此时只靠通知提醒。
            _ = try? Activity.request(attributes: attributes, content: content(endsAt: date))
        }
        scheduleRefresh()
    }

    /// 还有进行中的实时活动就排下一次后台刷新，否则撤销。实际何时执行由系统决定。
    static func scheduleRefresh() {
        let ongoing = Activity<OrderActivityAttributes>.activities.contains {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard ongoing else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func content(endsAt: Date) -> ActivityContent<OrderActivityAttributes.ContentState> {
        ActivityContent(state: .init(endsAt: endsAt), staleDate: endsAt)
    }
}
