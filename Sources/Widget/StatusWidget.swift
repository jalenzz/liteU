import AppIntents
import SwiftUI
import WidgetKit

@main
struct LiteUWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LiteUStatus", intent: SelectStoresIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .widgetURL(URL(string: "liteu://"))
        }
        .configurationDisplayName("LiteU")
        .description("显示已选洗衣房的空闲快照")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatusEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                stores: [StoreSnapshot(id: "1", name: "示例洗衣房", idle: 3, total: 10, waitMinutes: nil)],
                updatedAt: .now
            )
        )
    }

    func snapshot(for configuration: SelectStoresIntent, in context: Context) async -> StatusEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectStoresIntent, in context: Context) async -> Timeline<StatusEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectStoresIntent) -> StatusEntry {
        let snapshot = WidgetSnapshotStore.load()
        let chosen = configuration.chosenStores
        let stores: [StoreSnapshot]
        if chosen.isEmpty {
            stores = Array((snapshot?.stores ?? []).prefix(3))
        } else {
            let byID = Dictionary(uniqueKeysWithValues: (snapshot?.stores ?? []).map { ($0.id, $0) })
            stores = chosen.map { entity in
                byID[entity.id] ?? StoreSnapshot(id: entity.id, name: entity.name, idle: 0, total: 0, waitMinutes: nil)
            }
        }
        return StatusEntry(
            date: .now,
            snapshot: WidgetSnapshot(stores: stores, updatedAt: snapshot?.updatedAt ?? .now)
        )
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatusEntry

    var body: some View {
        Group {
            switch visibleStores.count {
            case 0:
                Text("选择洗衣房后显示空闲")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 1:
                oneStore(visibleStores[0])
            case 2:
                twoStores(visibleStores)
            default:
                threeStores(visibleStores)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var visibleStores: [StoreSnapshot] {
        Array((entry.snapshot?.stores ?? []).prefix(3))
    }

    private func oneStore(_ store: StoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(store.idle)")
                    .font(.system(size: family == .systemMedium ? 52 : 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(idleColor(store))
                Text("/\(store.total)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(detail(store))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func twoStores(_ stores: [StoreSnapshot]) -> some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 16) {
                    compactHero(stores[0])
                    Divider()
                    compactHero(stores[1])
                }
            } else {
                VStack(spacing: 0) {
                    stackedRow(stores[0])
                        .frame(maxHeight: .infinity)
                    Divider()
                    stackedRow(stores[1])
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func threeStores(_ stores: [StoreSnapshot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stores.enumerated()), id: \.element.id) { index, store in
                Group {
                    if family == .systemSmall {
                        stackedRow(store)
                    } else {
                        compactRow(store)
                    }
                }
                .frame(maxHeight: .infinity)
                if index < stores.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackedRow(_ store: StoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(store.idle)")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(idleColor(store))
                Text("/\(store.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                if let wait = store.waitMinutes {
                    Text("\(wait)分")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactHero(_ store: StoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(store.idle)")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(idleColor(store))
                Text("/\(store.total)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(detail(store))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func compactRow(_ store: StoreSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(store.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(store.idle)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(idleColor(store))
            Text("/\(store.total)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.tertiary)
            if let wait = store.waitMinutes {
                Text("\(wait)分")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func idleColor(_ store: StoreSnapshot) -> Color {
        store.idle == 0 ? .orange : .primary
    }

    private func detail(_ store: StoreSnapshot) -> String {
        if let wait = store.waitMinutes {
            return "最短等待 \(wait) 分钟"
        }
        if store.total > 0, store.idle == store.total {
            return "全部空闲"
        }
        return "空闲 \(store.idle) / \(store.total)"
    }
}
