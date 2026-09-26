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
                Button("使用当前位置", systemImage: "location") {
                    location.request()
                }
                .disabled(isLoading)
            } footer: {
                if let message = location.errorMessage {
                    Text(message)
                }
            }

            Section {
                DisclosureGroup("手动输入坐标") {
                    TextField("纬度，如 30.676", text: $latText)
                        .keyboardType(.decimalPad)
                    TextField("经度，如 104.094", text: $lontText)
                        .keyboardType(.decimalPad)
                    Button("查找") {
                        Task { await search() }
                    }
                    .disabled(isLoading)
                }
            } footer: {
                Text("无法使用当前位置时使用")
            }

            Section("附近洗衣房") {
                if isLoading && displayedStores.isEmpty {
                    ProgressView()
                }
                ForEach(displayedStores) { store in
                    let isSelected = selectedIDs.contains(store.id)
                    Button {
                        toggle(store)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(store.name)
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                if nearbyIDs.contains(store.id) {
                                    Text("洗衣机空闲 \(store.idle) / \(store.total)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .navigationTitle("管理洗衣房")
        .toolbar {
            if showsLogout {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出登录") { auth.clear() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { save() }
                    .disabled(selectedIDs.isEmpty || searchLatitude == nil)
            }
        }
        .alert("无法加载附近洗衣房", isPresented: Binding(
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

    /// 已保存的店按保存顺序在前，其余附近店按距离顺序在后。
    private var displayedStores: [NearbyStore] {
        let byID = Dictionary(uniqueKeysWithValues: nearby.map { ($0.id, $0) })
        let saved = selection.stores.map { byID[$0.id] ?? NearbyStore(id: $0.id, name: $0.name, idle: 0, total: 0) }
        return saved + nearby.filter { !savedIDs.contains($0.id) }
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
        let stores = displayedStores
            .filter { selectedIDs.contains($0.id) }
            .map { SelectedStore(id: $0.id, name: $0.name) }
        selection.save(PersistedSelection(stores: stores, latitude: searchLatitude!, longitude: searchLongitude!))
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}
