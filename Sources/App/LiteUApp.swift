import SwiftUI
import UserNotifications

@main
struct LiteUApp: App {
    @State private var auth = AuthStore()
    @State private var selection = StoreSelectionStore()
    @State private var orderStore = OrderStore()

    init() {
        AppSettings.registerDefaults()
        UNUserNotificationCenter.current().delegate = WasherNotification.presenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(selection)
                .environment(orderStore)
        }
    }
}

extension EnvironmentValues {
    @Entry var ujingClient = UjingClient.live()
}
