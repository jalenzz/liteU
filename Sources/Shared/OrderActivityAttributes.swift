import ActivityKit
import Foundation

struct OrderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }

    var orderID: String
    var title: String
    var storeName: String
    var kind: MachineKind
}
