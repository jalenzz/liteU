import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection

    var body: some View {
        NavigationStack {
            if auth.token == nil {
                LoginView()
            } else if selection.stores.isEmpty {
                StorePickerView()
            } else {
                StatusView()
            }
        }
    }
}
