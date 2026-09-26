import SwiftUI

enum AppSettings {
    static let showDryers = "showDryers"
    static let showShoeWashers = "showShoeWashers"
    static let remindBeforeEnd = "remindBeforeEnd"
}

@MainActor
@Observable
final class OrderStore {
    private(set) var running: [Order] = []
    private(set) var reminderError: String?

    func refreshRunning(client: UjingClient, token: String) async throws {
        running = try await client.runningOrders(token)
        await syncReminders()
    }

    func reset() async {
        running = []
        await syncReminders()
    }

    func syncReminders() async {
        let enabled = UserDefaults.standard.object(forKey: AppSettings.remindBeforeEnd) as? Bool ?? true
        do {
            try await OrderReminder.sync(enabled ? running : [])
            reminderError = nil
        } catch {
            reminderError = error.localizedDescription
        }
    }
}

struct OrdersView: View {
    private static let pageSize = 10

    @Environment(AuthStore.self) private var auth
    @Environment(OrderStore.self) private var orderStore
    @Environment(\.ujingClient) private var client
    @AppStorage(AppSettings.remindBeforeEnd) private var remindBeforeEnd = true

    @State private var history: [Order] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoadingHistory = false
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
                    Text(remindBeforeEnd ? orderStore.reminderError ?? "结束前 1 分钟会发通知提醒" : "结束提醒已在设置中关闭")
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
                                Task { await loadHistory() }
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
        .task { await reload() }
        .alert("查询失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        let token = auth.token!
        nextPage = 1
        hasMore = true
        async let running: Void = refreshRunning(token: token)
        await loadHistory()
        await running
    }

    private func refreshRunning(token: String) async {
        do {
            try await orderStore.refreshRunning(client: client, token: token)
        } catch {
            errorMessage = auth.message(for: error)
        }
    }

    private func loadHistory() async {
        guard hasMore, !isLoadingHistory, let token = auth.token else { return }
        let page = nextPage
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let items = try await client.historyOrders(page, Self.pageSize, token)
            history = page == 1 ? items : history + items
            nextPage = page + 1
            hasMore = items.count == Self.pageSize
        } catch {
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
    private static let dateFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current,
        calendar: Calendar(identifier: .gregorian)
    )

    var order: Order

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.title)
                    .font(.headline)
                Text([order.storeName, order.createdAt?.formatted(Self.dateFormat) ?? ""]
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
