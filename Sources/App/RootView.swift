import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection
    @Environment(OrderStore.self) private var orderStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.token == nil {
                NavigationStack {
                    LoginView()
                }
            } else if selection.stores.isEmpty {
                NavigationStack {
                    StorePickerView()
                }
            } else {
                MainTabView()
            }
        }
        .onChange(of: auth.token == nil) { _, loggedOut in
            if loggedOut {
                WidgetSnapshotStore.clear()
                WidgetCenter.shared.reloadAllTimelines()
                Task {
                    await orderStore.reset()
                    await WasherNotification.cancelAll()
                }
            }
        }
        // 锁屏时被后台刷新拉起的进程读不到钥匙串，解锁回到前台再读一次。
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && auth.token == nil {
                auth.load()
            }
        }
    }
}

private struct MainTabView: View {
    private static let refreshInterval: Duration = .seconds(60)

    @Environment(AuthStore.self) private var auth
    @Environment(OrderStore.self) private var orderStore
    @Environment(\.ujingClient) private var client
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.status

    private enum Tab {
        case status, orders, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                StatusView()
            }
            .tabItem {
                Label("洗衣房", systemImage: "washer")
            }
            .tag(Tab.status)

            NavigationStack {
                OrdersView()
            }
            .tabItem {
                Label("订单", systemImage: "receipt")
            }
            .badge(orderStore.running.count)
            .tag(Tab.orders)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
        .onOpenURL { url in
            if url == OrderActivityAttributes.ordersURL {
                tab = .orders
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            while (try? await Task.sleep(for: Self.refreshInterval)) != nil {
                _ = await orderStore.refreshRunning(client: client, auth: auth)
            }
        }
    }
}

private struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection
    @Environment(OrderStore.self) private var orderStore
    @AppStorage(AppSettings.showDryers) private var showDryers = true
    @AppStorage(AppSettings.showShoeWashers) private var showShoeWashers = true
    @AppStorage(AppSettings.remindBeforeEnd) private var remindBeforeEnd = true

    var body: some View {
        List {
            Section("账号") {
                LabeledContent("手机号", value: auth.mobile.map { "\($0.prefix(3))****\($0.suffix(4))" } ?? "重新登录后显示")
            }
            Section("显示的机器") {
                Toggle("烘干机", isOn: $showDryers)
                Toggle("洗鞋机", isOn: $showShoeWashers)
            }
            Section("通知") {
                Toggle("结束前 1 分钟提醒", isOn: $remindBeforeEnd)
                    .onChange(of: remindBeforeEnd) {
                        Task { await orderStore.syncReminders() }
                    }
            }
            Section {
                Button("退出登录", role: .destructive) {
                    selection.clearStores()
                    auth.clear()
                }
            }
        }
        .navigationTitle("设置")
    }
}
