import Foundation

enum WidgetSnapshotStore {
    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        AppGroup.defaults.set(try! JSONEncoder().encode(snapshot), forKey: AppGroup.snapshotKey)
    }
}
