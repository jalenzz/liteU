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

struct Order: Equatable, Sendable, Identifiable {
    var id: String
    var machineName: String
    var deviceNo: String
    var storeName: String
    var statusText: String
    var createdAt: Date?
    var endsAt: Date?

    var title: String {
        deviceNo.isEmpty ? machineName : "\(deviceNo)号\(machineName)"
    }
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

    static let deviceTypeNames = [
        1: "波轮机", 2: "滚筒机", 3: "烘干机", 4: "洗鞋机", 6: "大容量烘干", 8: "OTT波轮机",
        9: "10kg滚筒机", 10: "9kg烘干机", 11: "6.5kg波轮机", 12: "新10kg滚筒机", 13: "10kg干衣护理机",
    ]

    static let orderStatusTexts = [
        10: "已预约", 20: "已支付", 21: "启动中", 22: "自洁启动中", 24: "正在投放洗衣液", 29: "退单保护",
        30: "自洁中", 35: "自洁完成", 40: "运行中", 50: "订单完成", 51: "超时未支付", 52: "启动失败",
        53: "订单已取消", 54: "超时未启动", 60: "故障中", 61: "故障中",
    ]

    /// 官方 App 仅在自洁中、运行中按 `remainTime` 倒计时。
    static let countingDownStatuses: Set<Int> = [30, 40]

    static func order(_ dto: OrderDTO, now: Date) -> Order {
        let counting = !dto.isPaused && countingDownStatuses.contains(dto.status) && dto.remainTime > 0
        return Order(
            id: dto.orderId,
            machineName: deviceTypeNames[dto.deviceTypeId] ?? (dto.deviceTypeName.isEmpty ? "设备" : dto.deviceTypeName),
            deviceNo: dto.deviceNo,
            storeName: dto.storeName,
            statusText: dto.isPaused ? "机器暂停中" : orderStatusTexts[dto.status] ?? "状态 \(dto.status)",
            createdAt: try? Date(dto.createAt, strategy: .iso8601),
            endsAt: counting ? now.addingTimeInterval(TimeInterval(dto.remainTime)) : nil
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

struct OrderDTO: Equatable, Sendable {
    var orderId: String
    var deviceTypeId: Int
    var deviceTypeName: String
    var deviceNo: String
    var storeName: String
    var status: Int
    var isPaused: Bool
    var createAt: String
    var remainTime: Int
}
