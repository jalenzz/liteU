import Foundation

@MainActor
@Observable
final class StoreSelectionStore {
    private(set) var selection: PersistedSelection?

    var stores: [SelectedStore] { selection?.stores ?? [] }

    init() {
        load()
    }

    func load() {
        selection = AppGroup.loadSelection()
    }

    func save(_ selection: PersistedSelection) {
        self.selection = selection
        AppGroup.defaults.set(try! JSONEncoder().encode(selection), forKey: AppGroup.selectionKey)
    }

    func clearStores() {
        selection = nil
        AppGroup.defaults.removeObject(forKey: AppGroup.selectionKey)
    }
}
