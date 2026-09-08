import Foundation

enum AppGroup {
    static let id = "group.com.liteu.shared"
    static let snapshotKey = "widgetSnapshot"
    static let selectionKey = "selectedStores"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id)!
    }

    static func loadSelection() -> PersistedSelection? {
        guard let data = defaults.data(forKey: selectionKey) else { return nil }
        return try? JSONDecoder().decode(PersistedSelection.self, from: data)
    }
}
