import SwiftUI
import WidgetKit

struct StatusView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection
    @Environment(OrderStore.self) private var orderStore
    @Environment(\.ujingClient) private var client
    @AppStorage(AppSettings.showDryers) private var showDryers = true
    @AppStorage(AppSettings.showShoeWashers) private var showShoeWashers = true

    @State private var statuses: [StoreStatus] = []
    @State private var updatedAt: Date?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pickingStores = false
    @State private var notifyKeys: Set<String> = []
    @State private var notifyMessage: String?

    var body: some View {
        Group {
            if statuses.isEmpty && isLoading {
                ProgressView("正在查询…")
            } else {
                List {
                    ForEach(statuses) { store in
                        Section(store.name) {
                            if !store.found {
                                Text("这次附近结果里没有这家店")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(store.kinds.filter { isVisible($0.kind) }) { kind in
                                let key = WasherNotification.key(storeID: store.id, kind: kind.kind)
                                KindStatusRow(kind: kind, isArmed: notifyKeys.contains(key)) {
                                    await toggleNotify(store: store, kind: kind)
                                }
                            }
                        }
                    }
                    if let updatedAt {
                        Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("洗衣房")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("选择") { pickingStores = true }
            }
        }
        .sheet(isPresented: $pickingStores) {
            NavigationStack {
                StorePickerView(showsLogout: false)
            }
        }
        .alert("查询失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("通知", isPresented: Binding(
            get: { notifyMessage != nil },
            set: { if !$0 { notifyMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(notifyMessage ?? "")
        }
        .task(id: selection.stores.map(\.id).joined(separator: ",")) {
            await load()
            notifyKeys = await WasherNotification.pendingKeys()
        }
    }

    private func isVisible(_ kind: MachineKind) -> Bool {
        switch kind {
        case .washer: true
        case .dryer: showDryers
        case .shoe: showShoeWashers
        }
    }

    private func load() async {
        let token = auth.token!
        isLoading = true
        defer { isLoading = false }
        async let running: Void = refreshRunning(token: token)
        await loadStatuses(token: token)
        await running
    }

    private func loadStatuses(token: String) async {
        let saved = selection.selection!
        do {
            let result = try await client.loadStatuses(
                selected: saved.stores,
                latitude: saved.latitude,
                longitude: saved.longitude,
                token: token
            )
            statuses = result
            let now = Date()
            updatedAt = now
            WidgetSnapshotStore.save(LaundryMapping.snapshot(from: result, updatedAt: now))
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = auth.message(for: error)
        }
    }

    private func refreshRunning(token: String) async {
        do {
            try await orderStore.refreshRunning(client: client, token: token)
        } catch {
            errorMessage = auth.message(for: error)
        }
    }

    private func toggleNotify(store: StoreStatus, kind: KindStatus) async {
        let key = WasherNotification.key(storeID: store.id, kind: kind.kind)
        if notifyKeys.contains(key) {
            WasherNotification.cancel(key: key)
            notifyKeys.remove(key)
            return
        }
        do {
            try await WasherNotification.schedule(store: store, kind: kind)
            notifyKeys.insert(key)
        } catch is CancellationError {
            return
        } catch {
            notifyMessage = error.localizedDescription
        }
    }
}

private struct KindStatusRow: View {
    var kind: KindStatus
    var isArmed: Bool
    var onNotify: () async -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.kind.title)
                    .font(.headline)
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                Task { await onNotify() }
            } label: {
                Image(systemName: isArmed ? "bell.fill" : "bell")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .accessibilityLabel(isArmed ? "取消提醒" : "空闲前提醒")
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        var parts = ["空闲 \(kind.idle) / \(kind.total)"]
        if let wait = kind.waitMinutes {
            parts.append("最短等待 \(wait) 分钟")
        } else if kind.total > kind.idle {
            parts.append("最短等待暂不可用")
        } else {
            parts.append("全部空闲")
        }
        return parts.joined(separator: "  ")
    }
}
