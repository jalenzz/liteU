import Foundation
import os
import Testing
@testable import LiteU

struct CaptchaSignatureTests {
    @Test func hmacSignIsStable() {
        #expect(CaptchaSignature.sign(nonce: "abc", timestamp: 1) == "MKVw7yKpnI5XB4Pz32S6pmn+JkbnerrVcbItz2xroYQ=")
    }
}

struct PhoneTests {
    @Test(arguments: ["13800138000", "19900001111"])
    func validPhones(_ mobile: String) {
        #expect(PhoneNumber.isValid(mobile))
    }

    @Test(arguments: ["1380013800", "23800138000", "138001380001", ""])
    func invalidPhones(_ mobile: String) {
        #expect(!PhoneNumber.isValid(mobile))
    }
}

struct GeoCoordinateTests {
    @Test func rejectsLatitudeOutOfRange() {
        #expect(GeoCoordinate.parse(latitude: "104.094232", longitude: "30.676082") == nil)
    }

    @Test func acceptsChengdu() {
        let parsed = GeoCoordinate.parse(latitude: "30.676082", longitude: "104.094232")
        #expect(parsed?.0 == 30.676082)
        #expect(parsed?.1 == 104.094232)
    }
}

struct WasherNotifyTimingTests {
    @Test func notifiesTwoMinutesBeforeWaitEnds() {
        #expect(WasherNotifyTiming.delaySeconds(waitMinutes: 12) == 10 * 60)
    }

    @Test func firesImmediatelyWhenWaitAlreadyWithinLead() {
        #expect(WasherNotifyTiming.delaySeconds(waitMinutes: 2) == 0)
        #expect(WasherNotifyTiming.delaySeconds(waitMinutes: 1) == 0)
    }

    @Test func orderReminderFiresOneMinuteBeforeEnd() {
        let end = Date(timeIntervalSince1970: 1_000)
        #expect(OrderReminderTiming.fireDate(endsAt: end) == Date(timeIntervalSince1970: 940))
    }
}

struct LaundryMappingTests {
    @Test func washerCountsIgnoreNonWashers() {
        let counts = LaundryMapping.washerCounts(storeInfo: [
            StoreInfoItem(category: 1, num: 8, access: 2),
            StoreInfoItem(category: 1, num: 2, access: 1),
            StoreInfoItem(category: 2, num: 4, access: 4),
        ])
        #expect(counts.idle == 3)
        #expect(counts.total == 10)
    }

    @Test(arguments: [
        ("洗衣机", MachineKind.washer),
        ("滚筒", .washer),
        ("", .washer),
        ("烘干机", .dryer),
        ("洗烘套装干衣", .dryer),
        ("洗鞋机", .shoe),
    ])
    func machineKindFromTypeName(_ name: String, _ kind: MachineKind) {
        #expect(MachineKind(typeName: name) == kind)
    }

    @Test func kindsUseStoreInfoForWashersAndReserveForOthers() {
        let machines = LaundryMapping.machines(from: [
            ReserveDeviceDTO(device: .init(deviceTypeName: "洗衣机", free: 0, total: 4, waitTime: 20)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "滚筒", free: 0, total: 2, waitTime: 12)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "烘干机", free: 1, total: 2, waitTime: 5)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "洗烘套装干衣", free: 0, total: 1, waitTime: 3)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "洗鞋机", free: 0, total: 0, waitTime: 0)),
        ])
        let kinds = LaundryMapping.kinds(washerIdle: 1, washerTotal: 7, machines: machines)
        #expect(kinds == [
            KindStatus(kind: .washer, idle: 1, total: 7, waitMinutes: 12),
            KindStatus(kind: .dryer, idle: 1, total: 3, waitMinutes: 3),
        ])
    }

    @Test func waitMinutesIgnoresZero() {
        #expect(LaundryMapping.waitMinutes([
            MachineType(name: "a", kind: .washer, idle: 1, total: 2, waitMinutes: 0),
            MachineType(name: "b", kind: .washer, idle: 0, total: 2, waitMinutes: 8),
        ]) == 8)
    }

    private static func dto(status: Int, isPaused: Bool = false, remainTime: Int = 1550) -> OrderDTO {
        OrderDTO(
            orderId: "9",
            deviceTypeId: 3,
            deviceTypeName: "",
            deviceNo: "12",
            storeName: "3舍",
            status: status,
            isPaused: isPaused,
            createAt: "2026-09-22T10:05:51Z",
            remainTime: remainTime
        )
    }

    @Test func runningOrderEndsAfterRemainSeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let order = LaundryMapping.order(Self.dto(status: 40), now: now)
        #expect(order.title == "12号烘干机")
        #expect(order.statusText == "运行中")
        #expect(order.createdAt == Date(timeIntervalSince1970: 1_790_071_551))
        #expect(order.endsAt == now.addingTimeInterval(1550))
    }

    @Test(arguments: [
        (21, false, "启动中"),
        (40, true, "机器暂停中"),
        (50, false, "订单完成"),
        (99, false, "状态 99"),
    ])
    func orderWithoutCountdown(_ status: Int, _ isPaused: Bool, _ text: String) {
        let order = LaundryMapping.order(Self.dto(status: status, isPaused: isPaused), now: .now)
        #expect(order.statusText == text)
        #expect(order.endsAt == nil)
    }

    @Test func unknownDeviceTypeFallsBackToName() {
        var dto = Self.dto(status: 50)
        dto.deviceTypeId = 0
        dto.deviceTypeName = "吹风机"
        dto.deviceNo = ""
        #expect(LaundryMapping.order(dto, now: .now).title == "吹风机")
    }
}

struct DecodingTests {
    @Test func nearStoreDecodesIntIDAndWasherCounts() throws {
        let json = """
        {
          "id": 42,
          "name": "3舍1楼",
          "storeInfo": [
            {"category": 1, "num": 6, "access": 2},
            {"category": 2, "num": 3, "access": 1}
          ]
        }
        """.data(using: .utf8)!
        let store = try JSONDecoder().decode(NearStoreDTO.self, from: json)
        #expect(store.id == "42")
        #expect(store.name == "3舍1楼")
        let counts = LaundryMapping.washerCounts(storeInfo: store.storeInfo)
        #expect(counts.idle == 2)
        #expect(counts.total == 6)
    }

    @Test func envelopeLoginToken() throws {
        let json = """
        {"code":0,"data":{"token":"abc.def.ghi"}}
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(EnvelopeProbe.self, from: json)
        #expect(envelope.code == 0)
        #expect(envelope.data?.token == "abc.def.ghi")
    }

    @Test func snapshotRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            stores: [StoreSnapshot(id: "1", name: "店", idle: 1, total: 4, waitMinutes: 9)],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func queryEncodesPlusInSignature() {
        let signature = "MKVw7yKpnI5XB4Pz32S6pmn+JkbnerrVcbItz2xroYQ="
        let url = QueryURL.make(
            base: URL(string: "https://phoenix.ujing.online")!,
            path: "api/v1/wechat/captcha/create",
            query: [URLQueryItem(name: "signature", value: signature)]
        )
        #expect(url.absoluteString.contains("signature=MKVw7yKpnI5XB4Pz32S6pmn%2BJkbnerrVcbItz2xroYQ%3D"))
        #expect(!url.absoluteString.contains("pmn+J"))
    }

    @Test func orderDecodesServerFields() throws {
        let json = """
        [{
          "orderId": 123456,
          "orderNo": "20260922180550739848",
          "deviceTypeId": 2,
          "deviceNo": 7,
          "storeName": "3舍1楼",
          "status": "40",
          "isPauseStatus": false,
          "createAt": "2026-09-22T10:05:51Z",
          "remainTime": 1550,
          "workTime": 35
        }]
        """.data(using: .utf8)!
        let orders = try JSONDecoder().decode([OrderDTO].self, from: json)
        #expect(orders == [OrderDTO(
            orderId: "123456",
            deviceTypeId: 2,
            deviceTypeName: "",
            deviceNo: "7",
            storeName: "3舍1楼",
            status: 40,
            isPaused: false,
            createAt: "2026-09-22T10:05:51Z",
            remainTime: 1550
        )])
    }

    @Test func loadStatusesRequestsMachinesForFoundStores() async throws {
        let requested = OSAllocatedUnfairLock<[String]>(initialState: [])
        let client = UjingClient(
            sendCaptcha: { _ in },
            login: { _, _ in "" },
            nearbyStores: { _, _, _ in
                [
                    NearbyStore(id: "a", name: "满员", idle: 0, total: 4),
                    NearbyStore(id: "b", name: "空闲", idle: 3, total: 3),
                ]
            },
            machines: { storeId, _ in
                requested.withLock { $0.append(storeId) }
                return storeId == "a"
                    ? [MachineType(name: "洗衣机", kind: .washer, idle: 0, total: 4, waitMinutes: 15)]
                    : [MachineType(name: "烘干机", kind: .dryer, idle: 2, total: 2, waitMinutes: 0)]
            },
            runningOrders: { _ in [] },
            historyOrders: { _, _, _ in [] }
        )
        let statuses = try await client.loadStatuses(
            selected: [
                SelectedStore(id: "a", name: "满员"),
                SelectedStore(id: "b", name: "空闲"),
                SelectedStore(id: "c", name: "不见了"),
            ],
            latitude: 1,
            longitude: 2,
            token: "t"
        )
        #expect(statuses.map(\.id) == ["a", "b", "c"])
        #expect(requested.withLock { $0.sorted() } == ["a", "b"])
        #expect(statuses[0].waitMinutes == 15)
        #expect(statuses[1].waitMinutes == nil)
        #expect(statuses[1].kinds.map(\.kind) == [.washer, .dryer])
        #expect(statuses[2].found == false)
        #expect(statuses[2].kinds.isEmpty)
    }

    @Test func loadStatusesKeepsOtherStoresWhenMachinesFail() async throws {
        let client = UjingClient(
            sendCaptcha: { _ in },
            login: { _, _ in "" },
            nearbyStores: { _, _, _ in
                [
                    NearbyStore(id: "a", name: "坏", idle: 1, total: 4),
                    NearbyStore(id: "b", name: "好", idle: 3, total: 3),
                ]
            },
            machines: { storeId, _ in
                if storeId == "a" { throw UjingError.transport("超时") }
                return []
            },
            runningOrders: { _ in [] },
            historyOrders: { _, _, _ in [] }
        )
        let statuses = try await client.loadStatuses(
            selected: [SelectedStore(id: "a", name: "坏"), SelectedStore(id: "b", name: "好")],
            latitude: 1,
            longitude: 2,
            token: "t"
        )
        #expect(statuses.map(\.machinesFailed) == [true, false])
        #expect(statuses[0].kinds.map(\.kind) == [.washer])
    }

    @Test func loadStatusesPropagatesUnauthorized() async {
        let client = UjingClient(
            sendCaptcha: { _ in },
            login: { _, _ in "" },
            nearbyStores: { _, _, _ in [NearbyStore(id: "a", name: "店", idle: 1, total: 4)] },
            machines: { _, _ in throw UjingError.unauthorized },
            runningOrders: { _ in [] },
            historyOrders: { _, _, _ in [] }
        )
        await #expect(throws: UjingError.unauthorized) {
            try await client.loadStatuses(
                selected: [SelectedStore(id: "a", name: "店")],
                latitude: 1,
                longitude: 2,
                token: "t"
            )
        }
    }
}

private struct EnvelopeProbe: Decodable {
    var code: Int
    var data: LoginData?
}
