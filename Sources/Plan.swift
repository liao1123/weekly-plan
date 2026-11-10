import Combine
import Foundation

enum PlanSlot: Equatable {
    case goal(String)
    case day(String)
}

struct PlanTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var isDone = false
}

struct PlanDeadline: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var dueAt: Date
    var isDone = false

    var dateLabel: String {
        dueAt.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
    }
}

struct DeadlineCountdown {
    let dueAt: Date
    let now: Date

    var isOverdue: Bool { now >= dueAt }

    var label: String {
        let remaining = dueAt.timeIntervalSince(now)
        let seconds = Int(isOverdue ? floor(-remaining) : ceil(remaining))
        let days = seconds / 86_400
        let clock = String(format: "%02d:%02d:%02d", seconds / 3_600 % 24, seconds / 60 % 60, seconds % 60)
        let duration = days > 0 ? "\(days)天 \(clock)" : clock
        return isOverdue ? "已超时 \(duration)" : "还剩 \(duration)"
    }
}

struct Plan: Codable, Equatable {
    private var goals: [String: [PlanTask]] = [:]
    private var days: [String: [PlanTask]] = [:]
    private var notes: [String: String]?
    private var deadlines: [PlanDeadline]?

    var deadlineItems: [PlanDeadline] {
        get { deadlines ?? [] }
        set { deadlines = newValue.isEmpty ? nil : newValue }
    }

    var firstOpenDeadline: PlanDeadline? {
        deadlineItems.filter { !$0.isDone }.min { $0.dueAt < $1.dueAt }
    }

    subscript(slot: PlanSlot) -> [PlanTask] {
        get {
            switch slot {
            case .goal(let key): goals[key, default: []]
            case .day(let key): days[key, default: []]
            }
        }
        set {
            switch slot {
            case .goal(let key): goals[key] = newValue.isEmpty ? nil : newValue
            case .day(let key): days[key] = newValue.isEmpty ? nil : newValue
            }
        }
    }

    subscript(noteFor day: String) -> String {
        get { notes?[day] ?? "" }
        set {
            var updated = notes ?? [:]
            updated[day] = newValue.isEmpty ? nil : newValue
            notes = updated.isEmpty ? nil : updated
        }
    }
}

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

struct PlanDisk {
    let file: URL
    private static let planPath = "local.woxi.weekplan/计划.json"

    static func local() throws -> PlanDisk {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        )
        return PlanDisk(file: directory.appending(path: planPath))
    }

    func read() throws -> Plan {
        do {
            let bytes = try Data(contentsOf: file)
            return try JSONDecoder().decode(Plan.self, from: bytes)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Plan()
        }
    }

    func write(_ plan: Plan) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(plan)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try bytes.write(to: file, options: .atomic)
    }
}

@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var plan = Plan()
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    private let disk: () throws -> PlanDisk

    init(disk: @escaping () throws -> PlanDisk = PlanDisk.local) {
        self.disk = disk
        load()
    }

    func load() {
        do {
            plan = try disk().read()
            isReady = true
            errorMessage = nil
        } catch {
            isReady = false
            errorMessage = "无法读取本机计划。检查文件后可以重试。"
        }
    }

    func save(_ text: String, in slot: PlanSlot, editing id: UUID?) -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        return update(slot) { tasks in
            if let id {
                guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
                tasks[index].title = title
            } else {
                tasks.append(PlanTask(title: title))
            }
        }
    }

    func toggle(_ id: UUID, in slot: PlanSlot) {
        update(slot) { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[index].isDone.toggle()
        }
    }

    @discardableResult
    func remove(_ id: UUID, in slot: PlanSlot) -> Bool {
        update(slot) { tasks in
            tasks.removeAll(where: { $0.id == id })
        }
    }

    func saveNote(_ text: String, for day: String) -> Bool {
        var updated = plan
        updated[noteFor: day] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return save(updated)
    }

    func saveDeadline(_ text: String, dueAt: Date, editing id: UUID?) -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let minute = Calendar.current.dateInterval(of: .minute, for: dueAt)?.start ?? dueAt
        return updateDeadlines { deadlines in
            if let id {
                guard let index = deadlines.firstIndex(where: { $0.id == id }) else { return }
                deadlines[index].title = title
                deadlines[index].dueAt = minute
            } else {
                deadlines.append(PlanDeadline(title: title, dueAt: minute))
            }
        }
    }

    func toggleDeadline(_ id: UUID) {
        _ = updateDeadlines { deadlines in
            guard let index = deadlines.firstIndex(where: { $0.id == id }) else { return }
            deadlines[index].isDone.toggle()
        }
    }

    func removeDeadline(_ id: UUID) -> Bool {
        updateDeadlines { $0.removeAll { $0.id == id } }
    }

    private func updateDeadlines(_ change: (inout [PlanDeadline]) -> Void) -> Bool {
        var updated = plan
        change(&updated.deadlineItems)
        return save(updated)
    }

    @discardableResult
    private func update(_ slot: PlanSlot, _ change: (inout [PlanTask]) -> Void) -> Bool {
        var updated = plan
        change(&updated[slot])
        return save(updated)
    }

    private func save(_ updated: Plan) -> Bool {
        guard isReady else { return false }
        guard updated != plan else { return true }
        do {
            try disk().write(updated)
            plan = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存失败。请检查磁盘空间后重试。"
            return false
        }
    }
}
