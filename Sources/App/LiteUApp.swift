import SwiftUI
import UserNotifications

@main
struct LiteUApp: App {
    @State private var auth = AuthStore()
    @State private var selection = StoreSelectionStore()
    @State private var orderStore = OrderStore()

    init() {
        UNUserNotificationCenter.current().delegate = WasherNotification.presenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(selection)
                .environment(orderStore)
                .environment(\.ujingClient, .live())
        }
    }
}

private struct UjingClientKey: EnvironmentKey {
    static let defaultValue = UjingClient.live()
}

extension EnvironmentValues {
    var ujingClient: UjingClient {
        get { self[UjingClientKey.self] }
        set { self[UjingClientKey.self] = newValue }
    }
}
