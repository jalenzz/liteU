import ActivityKit
import SwiftUI
import WidgetKit

struct OrderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderActivityAttributes.self) { context in
            OrderLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.82))
                .activitySystemActionForegroundColor(context.attributes.kind.tint)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            let endsAt = context.state.endsAt
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    KindBadge(kind: kind, size: 46)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.isStale {
                            Label("已结束", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                        } else {
                            Countdown(endsAt: endsAt)
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundStyle(kind.tint)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.title)
                                .font(.headline)
                            if !context.attributes.storeName.isEmpty {
                                Text(context.attributes.storeName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(context.isStale ? "记得取走" : "\(endsAt.formatted(date: .omitted, time: .shortened)) 结束")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.tint)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "checkmark")
                        .fontWeight(.bold)
                        .foregroundStyle(kind.tint)
                } else {
                    Countdown(endsAt: endsAt)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(kind.tint)
                        .frame(width: endsAt.timeIntervalSinceNow >= 3600 ? 72 : 54)
                }
            } minimal: {
                Image(systemName: context.isStale ? "checkmark" : kind.symbol)
                    .fontWeight(.semibold)
                    .foregroundStyle(kind.tint)
            }
            .keylineTint(kind.tint)
        }
    }
}

private struct OrderLockScreenView: View {
    var context: ActivityViewContext<OrderActivityAttributes>

    var body: some View {
        let kind = context.attributes.kind
        HStack(spacing: 14) {
            KindBadge(kind: kind, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if !context.attributes.storeName.isEmpty {
                    Text(context.attributes.storeName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Group {
                    if context.isStale {
                        Label("已结束", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                    } else {
                        Countdown(endsAt: context.state.endsAt)
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .frame(width: context.state.endsAt.timeIntervalSinceNow >= 3600 ? 136 : 104, alignment: .trailing)
                    }
                }
                .foregroundStyle(kind.tint)
                Text(context.isStale ? "记得取走" : "\(context.state.endsAt.formatted(date: .omitted, time: .shortened)) 结束")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
        }
        .padding(16)
    }
}

private struct KindBadge: View {
    var kind: MachineKind
    var size: CGFloat

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(kind.tint)
            .frame(width: size, height: size)
            .background(kind.tint.opacity(0.2), in: Circle())
    }
}

private struct Countdown: View {
    var endsAt: Date

    var body: some View {
        Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .contentTransition(.numericText(countsDown: true))
    }
}

private extension MachineKind {
    var symbol: String {
        switch self {
        case .washer: "washer.fill"
        case .dryer: "dryer.fill"
        case .shoe: "shoe.fill"
        }
    }

    var tint: Color {
        switch self {
        case .washer: Color(red: 0.36, green: 0.78, blue: 1.0)
        case .dryer: Color(red: 1.0, green: 0.66, blue: 0.3)
        case .shoe: Color(red: 0.4, green: 0.88, blue: 0.64)
        }
    }
}
