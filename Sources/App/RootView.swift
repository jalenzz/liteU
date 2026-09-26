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
            Section {
                LabeledContent("登录状态", value: "已登录")
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
