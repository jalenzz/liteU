import SwiftUI
import UserNotifications

enum AppSettings {
    static let showDryers = "showDryers"
    static let showShoeWashers = "showShoeWashers"
    static let remindBeforeEnd = "remindBeforeEnd"

    /// `@AppStorage` 声明处的默认值须与这里一致。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [showDryers: true, showShoeWashers: true, remindBeforeEnd: true])
    }
}

@MainActor
@Observable
final class OrderStore {
    private(set) var running: [Order] = []
    private(set) var reminderError: String?
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// 返回需要提示给用户的错误文案，见 `AuthStore.message(for:)`。
    func refreshRunning(client: UjingClient, auth: AuthStore) async -> String? {
        do {
            running = try await client.runningOrders(auth.token!)
        } catch {
            return auth.message(for: error)
        }
        await syncReminders()
        return nil
    }

    func reset() async {
        running = []
        await syncReminders()
    }

    func syncReminders() async {
        let enabled = UserDefaults.standard.bool(forKey: AppSettings.remindBeforeEnd)
        notificationStatus = await WasherNotification.authorizationStatus()
        let authorized = [.authorized, .provisional, .ephemeral].contains(notificationStatus)
        do {
            try await OrderReminder.sync(enabled ? running : [], authorized: authorized)
            reminderError = nil
        } catch {
            reminderError = error.localizedDescription
        }
    }

    /// 用户拒绝时 `authorize` 会抛错，结果以 `notificationStatus` 为准。
    func requestNotifications() async {
        try? await WasherNotification.authorize()
        await syncReminders()
    }
}

struct OrdersView: View {
    private static let pageSize = 10

    @Environment(AuthStore.self) private var auth
    @Environment(OrderStore.self) private var orderStore
    @Environment(\.ujingClient) private var client
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.remindBeforeEnd) private var remindBeforeEnd = true

    @State private var history: [Order] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoadingHistory = false
    @State private var historyRequest = 0
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if orderStore.running.isEmpty {
                    Text("没有使用中的机器")
                        .foregroundStyle(.secondary)
                }
                ForEach(orderStore.running) { order in
                    RunningOrderRow(order: order)
                }
            } header: {
                Text("使用中")
            } footer: {
                if !orderStore.running.isEmpty {
                    reminderFooter
                }
            }

            Section("最近订单") {
                if history.isEmpty && !isLoadingHistory {
                    Text("暂无订单")
                        .foregroundStyle(.secondary)
                }
                ForEach(history) { order in
                    HistoryOrderRow(order: order)
                        .onAppear {
                            if order.id == history.last?.id {
                                Task { await loadMore() }
                            }
                        }
                }
                if isLoadingHistory {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("订单")
        .refreshable { await reload() }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await reload()
        }
        .errorAlert("查询失败", message: $errorMessage)
    }

    @ViewBuilder
    private var reminderFooter: some View {
        if !remindBeforeEnd {
            Text("结束提醒已在设置中关闭")
        } else {
            switch orderStore.notificationStatus {
            case .notDetermined:
                Button("允许通知，结束前 1 分钟提醒") {
                    Task { await orderStore.requestNotifications() }
                }
            case .denied:
                Button("通知已关闭，前往系统设置开启") {
                    openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                }
            default:
                Text(orderStore.reminderError ?? "结束前 1 分钟会发通知提醒")
            }
        }
    }

    private func reload() async {
        async let runningError = orderStore.refreshRunning(client: client, auth: auth)
        await loadHistory(page: 1)
        if let message = await runningError {
            errorMessage = message
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingHistory else { return }
        await loadHistory(page: nextPage)
    }

    /// 只有最后一次发起的请求能写入结果，避免下拉刷新和翻页交错返回时拼错列表。
    private func loadHistory(page: Int) async {
        historyRequest += 1
        let request = historyRequest
        isLoadingHistory = true
        defer {
            if request == historyRequest { isLoadingHistory = false }
        }
        do {
            let items = try await client.historyOrders(page, Self.pageSize, auth.token!)
            guard request == historyRequest else { return }
            history = page == 1 ? items : history + items
            nextPage = page + 1
            hasMore = items.count == Self.pageSize
        } catch {
            guard request == historyRequest else { return }
            errorMessage = auth.message(for: error)
        }
    }
}

private struct RunningOrderRow: View {
    var order: Order

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.title)
                    .font(.headline)
                Text([order.storeName, order.statusText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let endsAt = order.endsAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true)
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text("\(endsAt.formatted(date: .omitted, time: .shortened)) 结束")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryOrderRow: View {
    var order: Order

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.title)
                    .font(.headline)
                Text([order.storeName, order.createdAt?.formatted(.dateTime.year().month().day().hour().minute()) ?? ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(order.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
