import Foundation

enum MachineKind: String, CaseIterable, Sendable {
    case washer, dryer, shoe

    init(typeName: String) {
        if typeName.contains("鞋") {
            self = .shoe
        } else if typeName.contains("烘干") || typeName.contains("干衣") {
            self = .dryer
        } else {
            self = .washer
        }
    }

    var title: String {
        switch self {
        case .washer: "洗衣机"
        case .dryer: "烘干机"
        case .shoe: "洗鞋机"
        }
    }
}

struct MachineType: Equatable, Sendable, Identifiable {
    var name: String
    var kind: MachineKind
    var idle: Int
    var total: Int
    var waitMinutes: Int

    var id: String { name }
}

struct KindStatus: Equatable, Sendable, Identifiable {
    var kind: MachineKind
    var idle: Int
    var total: Int
    var waitMinutes: Int?

    var id: MachineKind { kind }
}

struct StoreStatus: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var idle: Int
    var total: Int
    var machines: [MachineType]
    var found: Bool

    var kinds: [KindStatus] {
        LaundryMapping.kinds(washerIdle: idle, washerTotal: total, machines: machines)
    }

    var waitMinutes: Int? {
        kinds.first { $0.kind == .washer }?.waitMinutes
    }
}

struct RunningOrder: Equatable, Sendable, Identifiable {
    var id: String
    var machineName: String
    var storeName: String
    var statusText: String
    var endsAt: Date?
}

struct SelectedStore: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
}

struct PersistedSelection: Codable, Equatable, Sendable {
    var stores: [SelectedStore]
    var latitude: Double
    var longitude: Double
}

struct StoreSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var idle: Int
    var total: Int
    var waitMinutes: Int?
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    var stores: [StoreSnapshot]
    var updatedAt: Date
}

enum LaundryMapping {
    static func washerCounts(storeInfo: [StoreInfoItem]) -> (idle: Int, total: Int) {
        let washers = storeInfo.filter { $0.category == 1 }
        return (
            idle: washers.reduce(0) { $0 + $1.access },
            total: washers.reduce(0) { $0 + $1.num }
        )
    }

    static func machines(from devices: [ReserveDeviceDTO]) -> [MachineType] {
        devices.map { item in
            let device = item.device
            let name = device.deviceTypeName.isEmpty ? "洗衣机" : device.deviceTypeName
            return MachineType(
                name: name,
                kind: MachineKind(typeName: name),
                idle: device.free,
                total: device.total,
                waitMinutes: device.waitTime
            )
        }
    }

    static func waitMinutes(_ machines: [MachineType]) -> Int? {
        machines.map(\.waitMinutes).filter { $0 > 0 }.min()
    }

    static func kinds(washerIdle: Int, washerTotal: Int, machines: [MachineType]) -> [KindStatus] {
        MachineKind.allCases.compactMap { kind in
            let group = machines.filter { $0.kind == kind }
            let idle = kind == .washer ? washerIdle : group.reduce(0) { $0 + $1.idle }
            let total = kind == .washer ? washerTotal : group.reduce(0) { $0 + $1.total }
            guard total > 0 else { return nil }
            return KindStatus(kind: kind, idle: idle, total: total, waitMinutes: waitMinutes(group))
        }
    }

    static func runningOrder(_ detail: OrderDetailDTO, now: Date) -> RunningOrder {
        RunningOrder(
            id: detail.orderId,
            machineName: detail.deviceTypeName.isEmpty ? "使用中的机器" : detail.deviceTypeName,
            storeName: detail.storeName,
            statusText: detail.statusRemark,
            endsAt: detail.remainTime > 0 ? now.addingTimeInterval(TimeInterval(detail.remainTime)) : nil
        )
    }

    static func snapshot(from statuses: [StoreStatus], updatedAt: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            stores: statuses.map {
                StoreSnapshot(id: $0.id, name: $0.name, idle: $0.idle, total: $0.total, waitMinutes: $0.waitMinutes)
            },
            updatedAt: updatedAt
        )
    }
}

struct StoreInfoItem: Equatable, Sendable {
    var category: Int
    var num: Int
    var access: Int
}

struct ReserveDeviceDTO: Equatable, Sendable {
    var device: ReserveDeviceFields
}

struct ReserveDeviceFields: Equatable, Sendable {
    var deviceTypeName: String
    var free: Int
    var total: Int
    var waitTime: Int
}

struct OrderDetailDTO: Equatable, Sendable {
    var orderId: String
    var statusRemark: String
    var remainTime: Int
    var deviceTypeName: String
    var storeName: String
}
