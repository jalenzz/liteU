import SwiftUI
import WidgetKit

struct StatusView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoreSelectionStore.self) private var selection
    @Environment(\.ujingClient) private var client

    @State private var statuses: [StoreStatus] = []
    @State private var updatedAt: Date?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pickingStores = false
    @State private var notifyIDs: Set<String> = []
    @State private var notifyMessage: String?

    var body: some View {
        Group {
            if statuses.isEmpty && isLoading {
                ProgressView("正在查询…")
            } else {
                List {
                    ForEach(statuses) { store in
                        StoreStatusRow(store: store, isArmed: notifyIDs.contains(store.id)) {
                            await toggleNotify(store)
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
        .navigationTitle("洗衣机")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("退出") { auth.clear() }
            }
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
            notifyIDs = await WasherNotification.pendingStoreIDs()
        }
    }

    private func load() async {
        let saved = selection.selection!
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.loadStatuses(
                selected: saved.stores,
                latitude: saved.latitude,
                longitude: saved.longitude,
                token: auth.token!
            )
            statuses = result
            let now = Date()
            updatedAt = now
            WidgetSnapshotStore.save(LaundryMapping.snapshot(from: result, updatedAt: now))
            WidgetCenter.shared.reloadAllTimelines()
        } catch is CancellationError {
            return
        } catch let error as UjingError where error.isUnauthorized {
            auth.clear()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleNotify(_ store: StoreStatus) async {
        if notifyIDs.contains(store.id) {
            WasherNotification.cancel(storeID: store.id)
            notifyIDs.remove(store.id)
            return
        }
        do {
            try await WasherNotification.schedule(store: store)
            notifyIDs.insert(store.id)
        } catch is CancellationError {
            return
        } catch {
            notifyMessage = error.localizedDescription
        }
    }
}

private struct StoreStatusRow: View {
    var store: StoreStatus
    var isArmed: Bool
    var onNotify: () async -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.name)
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
        if !store.found {
            return "这次附近结果里没有这家店"
        }
        var parts = ["空闲 \(store.idle) / \(store.total)"]
        if let wait = store.waitMinutes {
            parts.append("最短等待 \(wait) 分钟")
        } else if store.total > store.idle {
            parts.append("最短等待暂不可用")
        } else if store.total > 0 {
            parts.append("全部空闲")
        }
        return parts.joined(separator: "  ")
    }
}
