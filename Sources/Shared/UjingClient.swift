import Foundation

struct NearbyStore: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var idle: Int
    var total: Int
}

struct UjingClient: Sendable {
    var sendCaptcha: @Sendable (_ mobile: String) async throws -> Void
    var login: @Sendable (_ mobile: String, _ captcha: String) async throws -> String
    var nearbyStores: @Sendable (_ lat: Double, _ lont: Double, _ token: String) async throws -> [NearbyStore]
    var machines: @Sendable (_ storeId: String, _ token: String) async throws -> [MachineType]
}

extension UjingClient {
    func loadStatuses(
        selected: [SelectedStore],
        latitude: Double,
        longitude: Double,
        token: String
    ) async throws -> [StoreStatus] {
        let nearby = try await nearbyStores(latitude, longitude, token)
        let byID = Dictionary(uniqueKeysWithValues: nearby.map { ($0.id, $0) })
        return try await withThrowingTaskGroup(of: (Int, StoreStatus).self) { group in
            for (index, store) in selected.enumerated() {
                group.addTask {
                    let near = byID[store.id]
                    var machines: [MachineType] = []
                    if let near, near.total > near.idle {
                        machines = try await self.machines(store.id, token)
                    }
                    return (
                        index,
                        StoreStatus(
                            id: store.id,
                            name: near?.name ?? store.name,
                            idle: near?.idle ?? 0,
                            total: near?.total ?? 0,
                            machines: machines,
                            waitMinutes: LaundryMapping.waitMinutes(machines),
                            found: near != nil
                        )
                    )
                }
            }
            var pairs: [(Int, StoreStatus)] = []
            for try await pair in group {
                pairs.append(pair)
            }
            return pairs.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func live(session: URLSession = .shared) -> UjingClient {
        let cache = WaitCache()
        let transport = UjingTransport(session: session)
        return UjingClient(
            sendCaptcha: { mobile in
                guard PhoneNumber.isValid(mobile) else { throw UjingError.invalidPhone }
                let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                let timestamp = Int(Date().timeIntervalSince1970)
                _ = try await transport.get(
                    path: "api/v1/wechat/captcha/create",
                    query: [
                        URLQueryItem(name: "mobile", value: mobile),
                        URLQueryItem(name: "type", value: "1"),
                        URLQueryItem(name: "nonce", value: nonce),
                        URLQueryItem(name: "timestamp", value: String(timestamp)),
                        URLQueryItem(name: "signature", value: CaptchaSignature.sign(nonce: nonce, timestamp: timestamp)),
                    ],
                    headers: UjingTransport.loginHeaders
                ) as EmptyData
            },
            login: { mobile, captcha in
                guard PhoneNumber.isValid(mobile) else { throw UjingError.invalidPhone }
                guard CaptchaCode.isValid(captcha) else { throw UjingError.invalidCaptcha }
                let data: LoginData = try await transport.post(
                    path: "api/v1/login",
                    body: ["mobile": mobile, "captcha": captcha],
                    headers: UjingTransport.loginHeaders
                )
                guard !data.token.isEmpty else {
                    throw UjingError.api(code: 0, message: "登录响应缺少 token")
                }
                return data.token
            },
            nearbyStores: { lat, lont, token in
                let payload: NearData = try await transport.get(
                    path: "api/v1/stores/near",
                    query: [
                        URLQueryItem(name: "lat", value: String(lat)),
                        URLQueryItem(name: "lont", value: String(lont)),
                        URLQueryItem(name: "scope", value: "2000"),
                        URLQueryItem(name: "page", value: "1"),
                        URLQueryItem(name: "size", value: "50"),
                        URLQueryItem(name: "mode", value: "BA"),
                    ],
                    headers: UjingTransport.queryHeaders(token: token)
                )
                return payload.storeList.map { store in
                    let counts = LaundryMapping.washerCounts(storeInfo: store.storeInfo)
                    return NearbyStore(id: store.id, name: store.name, idle: counts.idle, total: counts.total)
                }
            },
            machines: { storeId, token in
                if let cached = await cache.value(for: storeId) {
                    return cached
                }
                let payload: ReserveData = try await transport.get(
                    path: "api/v1/devices/reserve",
                    query: [URLQueryItem(name: "storeId", value: storeId)],
                    headers: UjingTransport.queryHeaders(token: token)
                )
                let machines = LaundryMapping.machines(from: payload.devices)
                await cache.store(machines, for: storeId)
                return machines
            }
        )
    }
}

actor WaitCache {
    private var items: [String: (Date, [MachineType])] = [:]

    func value(for id: String) -> [MachineType]? {
        guard let (at, value) = items[id], Date().timeIntervalSince(at) < 60 else { return nil }
        return value
    }

    func store(_ value: [MachineType], for id: String) {
        items[id] = (Date(), value)
    }
}

struct EmptyData: Decodable {}

struct LoginData: Decodable {
    var token: String
}

struct NearData: Decodable {
    var storeList: [NearStoreDTO] = []
}

struct NearStoreDTO: Decodable {
    var id: String
    var name: String
    var storeInfo: [StoreInfoItem]

    enum CodingKeys: String, CodingKey {
        case id, name, storeInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try FlexibleID.decode(container, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        storeInfo = try container.decodeIfPresent([StoreInfoItem].self, forKey: .storeInfo) ?? []
    }
}

struct ReserveData: Decodable {
    var devices: [ReserveDeviceDTO]
}

struct UjingTransport: Sendable {
    var session: URLSession
    var baseURL = URL(string: "https://phoenix.ujing.online")!

    static let loginHeaders = [
        "x-app-code": "BO",
        "x-app-version": "1.1.0",
    ]

    static func queryHeaders(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "x-app-code": "ZA",
            "x-app-version": "2.4.18",
        ]
    }

    func get<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) async throws -> T {
        var request = URLRequest(url: QueryURL.make(base: baseURL, path: path, query: query))
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try decode(try await data(for: request))
    }

    func post<T: Decodable>(
        path: String,
        body: [String: String],
        headers: [String: String]
    ) async throws -> T {
        var request = URLRequest(url: QueryURL.make(base: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONEncoder().encode(body)
        return try decode(try await data(for: request))
    }

    private func data(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UjingError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw UjingError.unauthorized
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if envelope.code == 401 {
            throw UjingError.unauthorized
        }
        if envelope.code != 0 {
            throw UjingError.api(
                code: envelope.code,
                message: envelope.msg ?? envelope.message ?? "请求失败"
            )
        }
        if T.self == EmptyData.self {
            return EmptyData() as! T
        }
        guard let value = envelope.data else {
            throw UjingError.api(code: envelope.code, message: "响应缺少 data")
        }
        return value
    }
}

private struct Envelope<T: Decodable>: Decodable {
    var code: Int
    var msg: String?
    var message: String?
    var data: T?
}

enum QueryURL {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func make(base: URL, path: String, query: [URLQueryItem] = []) -> URL {
        let pathURL = base.appending(path: path)
        guard !query.isEmpty else { return pathURL }
        let encoded = query.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed)!
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed)!
            return "\(name)=\(value)"
        }.joined(separator: "&")
        return URL(string: "\(pathURL.absoluteString)?\(encoded)")!
    }
}

enum FlexibleID {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> String {
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "id")
    }
}

extension StoreInfoItem: Decodable {
    enum CodingKeys: String, CodingKey {
        case category, num, access
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = JSONNumber.int(container, forKey: .category)
        num = JSONNumber.int(container, forKey: .num)
        access = JSONNumber.int(container, forKey: .access)
    }
}

extension ReserveDeviceDTO: Decodable {
    enum CodingKeys: String, CodingKey {
        case device
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decode(ReserveDeviceFields.self, forKey: .device)
    }
}

extension ReserveDeviceFields: Decodable {
    enum CodingKeys: String, CodingKey {
        case deviceTypeName, free, total, waitTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceTypeName = try container.decodeIfPresent(String.self, forKey: .deviceTypeName) ?? "洗衣机"
        free = JSONNumber.int(container, forKey: .free)
        total = JSONNumber.int(container, forKey: .total)
        waitTime = JSONNumber.int(container, forKey: .waitTime)
    }
}

enum JSONNumber {
    static func int<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decode(String.self, forKey: key), let parsed = Int(value) { return parsed }
        return 0
    }
}
