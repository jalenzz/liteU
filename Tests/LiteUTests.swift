import Foundation
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

    @Test func machinesDropDryersAndTakeMinWait() {
        let machines = LaundryMapping.machines(from: [
            ReserveDeviceDTO(device: .init(deviceTypeName: "洗衣机", free: 0, total: 4, waitTime: 20)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "烘干机", free: 1, total: 2, waitTime: 5)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "洗烘套装干衣", free: 0, total: 1, waitTime: 3)),
            ReserveDeviceDTO(device: .init(deviceTypeName: "滚筒", free: 0, total: 2, waitTime: 12)),
        ])
        #expect(machines.map(\.name) == ["洗衣机", "滚筒"])
        #expect(LaundryMapping.waitMinutes(machines) == 12)
    }

    @Test func waitMinutesIgnoresZero() {
        #expect(LaundryMapping.waitMinutes([
            MachineType(name: "a", idle: 1, total: 2, waitMinutes: 0),
            MachineType(name: "b", idle: 0, total: 2, waitMinutes: 8),
        ]) == 8)
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

    @Test func loadStatusesRequestsWaitOnlyWhenBusy() async throws {
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
                #expect(storeId == "a")
                return [MachineType(name: "洗衣机", idle: 0, total: 4, waitMinutes: 15)]
            }
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
        #expect(statuses[0].waitMinutes == 15)
        #expect(statuses[1].waitMinutes == nil)
        #expect(statuses[2].found == false)
    }
}

private struct EnvelopeProbe: Decodable {
    var code: Int
    var data: LoginData?
}
