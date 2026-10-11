import ActivityKit
import Foundation

struct OrderActivityAttributes: ActivityAttributes {
    static let ordersURL = URL(string: "liteu://orders")!

    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }

    var orderID: String
    var title: String
    var storeName: String
    var kind: MachineKind
}
