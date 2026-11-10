import Foundation

struct PlanCalendar {
    var calendar: Calendar

    init(timeZone: TimeZone = .autoupdatingCurrent) {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
    }

    func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    func week(from date: Date, offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart(for: date))!
    }

    func dates(inWeekOf date: Date) -> [Date] {
        let start = weekStart(for: date)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    func monthGridDates(for date: Date) -> [Date] {
        let month = calendar.dateInterval(of: .month, for: date)!
        let first = weekStart(for: month.start)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)!
        let end = week(from: lastDay, offset: 1)
        let count = calendar.dateComponents([.day], from: first, to: end).day!
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func shortDate(_ date: Date) -> String {
        "\(calendar.component(.month, from: date)).\(calendar.component(.day, from: date))"
    }

    func weekday(_ date: Date) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][
            calendar.component(.weekday, from: date) - 1
        ]
    }

    func weekTitle(from start: Date, to end: Date) -> String {
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let endPrefix = startYear == endYear ? "" : "\(endYear)年 "
        return "\(startYear)年 \(shortDate(start)) – \(endPrefix)\(shortDate(end))"
    }
}
