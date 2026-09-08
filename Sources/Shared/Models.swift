import Foundation

struct MachineType: Equatable, Sendable, Identifiable {
    var name: String
    var idle: Int
    var total: Int
    var waitMinutes: Int

    var id: String { name }
}

struct StoreStatus: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var idle: Int
    var total: Int
    var machines: [MachineType]
    var waitMinutes: Int?
    var found: Bool
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
        devices.compactMap { item in
            let device = item.device
            let name = device.deviceTypeName
            if name.contains("烘干") || name.contains("干衣") {
                return nil
            }
            return MachineType(
                name: name.isEmpty ? "洗衣机" : name,
                idle: device.free,
                total: device.total,
                waitMinutes: device.waitTime
            )
        }
    }

    static func waitMinutes(_ machines: [MachineType]) -> Int? {
        machines.map(\.waitMinutes).filter { $0 > 0 }.min()
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
