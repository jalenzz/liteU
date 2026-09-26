import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection

    var body: some View {
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
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                StatusView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }

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

    var body: some View {
        List {
            Section("账号") {
                LabeledContent("手机号", value: auth.mobile.map { "\($0.prefix(3))****\($0.suffix(4))" } ?? "重新登录后显示")
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
