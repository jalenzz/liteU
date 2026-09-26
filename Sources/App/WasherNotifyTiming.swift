import Foundation

enum WasherNotifyTiming {
    static let leadMinutes = 2

    static func delaySeconds(waitMinutes: Int) -> TimeInterval {
        TimeInterval(max(waitMinutes - leadMinutes, 0) * 60)
    }
}

enum OrderReminderTiming {
    static let leadSeconds: TimeInterval = 60

    static func fireDate(endsAt: Date) -> Date {
        endsAt.addingTimeInterval(-leadSeconds)
    }
}
