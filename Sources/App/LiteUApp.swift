import SwiftUI
import UserNotifications

@main
struct LiteUApp: App {
    @State private var auth = AuthStore()
    @State private var selection = StoreSelectionStore()

    init() {
        UNUserNotificationCenter.current().delegate = WasherNotification.presenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(selection)
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
