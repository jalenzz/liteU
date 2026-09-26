import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection
    @Environment(OrderStore.self) private var orderStore

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
    }
}

private struct MainTabView: View {
    @Environment(OrderStore.self) private var orderStore

    var body: some View {
        TabView {
            NavigationStack {
                StatusView()
            }
            .tabItem {
                Label("洗衣房", systemImage: "washer")
            }

            NavigationStack {
                OrdersView()
            }
            .tabItem {
                Label("订单", systemImage: "receipt")
            }
            .badge(orderStore.running.count)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }
}

private struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
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
                    auth.clear()
                }
            }
        }
        .navigationTitle("设置")
    }
}
