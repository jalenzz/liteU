import Foundation

enum WasherNotifyTiming {
    static let leadMinutes = 2

    static func delaySeconds(waitMinutes: Int) -> TimeInterval {
        TimeInterval(max(waitMinutes - leadMinutes, 0) * 60)
    }
}
