import SwiftUI
import WidgetKit

struct StorePickerView: View {
    var showsLogout = true

    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection
    @Environment(\.ujingClient) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var location = LocationProvider()
    @State private var latText = ""
    @State private var lontText = ""
    @State private var nearby: [NearbyStore] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchLatitude: Double?
    @State private var searchLongitude: Double?

    var body: some View {
        List {
            Section {
                Button("定位附近洗衣房") {
                    location.request()
                }
                .disabled(isLoading)
            } footer: {
                Text(location.errorMessage ?? "用当前定位列出附近店。")
            }

            Section {
                TextField("纬度，如 30.676", text: $latText)
                    .keyboardType(.decimalPad)
                TextField("经度，如 104.094", text: $lontText)
                    .keyboardType(.decimalPad)
                Button("按坐标查找") {
                    Task { await search() }
                }
                .disabled(isLoading)
            } header: {
                Text("手动坐标")
            } footer: {
                Text("请手动填写坐标")
            }

            Section("附近洗衣房") {
                if isLoading && displayedStores.isEmpty {
                    ProgressView()
                }
                ForEach(displayedStores) { store in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(store.name)
                            if nearbyIDs.contains(store.id) {
                                Text("空闲 \(store.idle) / \(store.total)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedIDs.contains(store.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(store) }
                }
            }
        }
        .navigationTitle("选择洗衣房")
        .toolbar {
            if showsLogout {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出登录") { auth.clear() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(selectedIDs.isEmpty || searchLatitude == nil)
            }
        }
        .alert("无法加载附近店", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            selectedIDs = Set(selection.stores.map(\.id))
            if let saved = selection.selection {
                latText = String(saved.latitude)
                lontText = String(saved.longitude)
                searchLatitude = saved.latitude
                searchLongitude = saved.longitude
                await search()
            }
        }
        .onChange(of: location.fixID) { _, _ in
            applyLocation()
            Task { await search() }
        }
    }

    private var displayedStores: [NearbyStore] {
        let stores: [NearbyStore]
        if nearby.isEmpty {
            stores = selection.stores.map { NearbyStore(id: $0.id, name: $0.name, idle: 0, total: 0) }
        } else {
            var merged = nearby
            let ids = Set(nearby.map(\.id))
            for store in selection.stores where !ids.contains(store.id) {
                merged.append(NearbyStore(id: store.id, name: store.name, idle: 0, total: 0))
            }
            stores = merged
        }
        return stores.filter { savedIDs.contains($0.id) } + stores.filter { !savedIDs.contains($0.id) }
    }

    private var nearbyIDs: Set<String> {
        Set(nearby.map(\.id))
    }

    private var savedIDs: Set<String> {
        Set(selection.stores.map(\.id))
    }

    private func applyLocation() {
        guard let coordinate = location.coordinate else { return }
        latText = String(coordinate.latitude)
        lontText = String(coordinate.longitude)
    }

    private func toggle(_ store: NearbyStore) {
        if selectedIDs.contains(store.id) {
            selectedIDs.remove(store.id)
        } else {
            selectedIDs.insert(store.id)
        }
    }

    private func search() async {
        guard let pair = GeoCoordinate.parse(latitude: latText, longitude: lontText) else {
            errorMessage = GeoCoordinate.errorMessage(latitude: latText, longitude: lontText)!
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            nearby = try await client.nearbyStores(pair.0, pair.1, auth.token!)
            searchLatitude = pair.0
            searchLongitude = pair.1
        } catch is CancellationError {
            return
        } catch let error as UjingError where error.isUnauthorized {
            auth.clear()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let lat = searchLatitude!
        let lont = searchLongitude!
        var byID = Dictionary(uniqueKeysWithValues: selection.stores.map { ($0.id, $0) })
        for store in nearby {
            byID[store.id] = SelectedStore(id: store.id, name: store.name)
        }
        let stores = selectedIDs.map { byID[$0]! }
        selection.save(PersistedSelection(stores: stores, latitude: lat, longitude: lont))
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}
