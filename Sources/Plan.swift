import Combine
import Darwin
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

    func widgetSummary(at date: Date, calendar: PlanCalendar = PlanCalendar()) -> WidgetSummary {
        let today = calendar.dayKey(date)
        let thisWeek = calendar.dayKey(calendar.weekStart(for: date))
        let upcomingGoals = goals.filter { $0.key >= thisWeek }.mapValues { widgetTasks($0, limit: 2) }
        var upcomingDays = days.filter { $0.key >= today }.mapValues {
            WidgetDaySummary(tasks: widgetTasks($0, limit: 4))
        }
        for (day, note) in notes ?? [:] where day >= today {
            upcomingDays[day, default: WidgetDaySummary()].note = String(note.prefix(160))
        }
        let deadline = firstOpenDeadline.map {
            WidgetDeadlineSummary(title: String($0.title.prefix(100)), dueAt: $0.dueAt)
        }
        return WidgetSummary(goals: upcomingGoals, days: upcomingDays, deadline: deadline)
    }

    private func widgetTasks(_ tasks: [PlanTask], limit: Int) -> WidgetTaskList {
        WidgetTaskList(
            items: tasks.prefix(limit).map { WidgetTaskSummary(title: String($0.title.prefix(120)), isDone: $0.isDone) },
            count: tasks.count,
            completed: tasks.filter(\.isDone).count
        )
    }
}

struct PlanDisk {
    let file: URL
    private static let planPath = "\(WidgetSummary.storageDirectory)/计划.json"

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

    func withWriteLock<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Lock a sibling file so atomic replacements leave the lock in place.
        let lock = file.appendingPathExtension("lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return try action()
    }
}

@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var plan = Plan()
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    private let disk: () throws -> PlanDisk
    private let planDidChange: @MainActor (Plan) -> Void

    init(
        disk: @escaping () throws -> PlanDisk = PlanDisk.local,
        planDidChange: @escaping @MainActor (Plan) -> Void = { _ in }
    ) {
        self.disk = disk
        self.planDidChange = planDidChange
        load()
    }

    func load() {
        do {
            let disk = try disk()
            plan = try disk.read()
            isReady = true
            errorMessage = nil
            try? disk.withWriteLock {
                let latest = try disk.read()
                if plan != latest { plan = latest }
                planDidChange(latest)
            }
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
        guard let isDone = plan[slot].first(where: { $0.id == id })?.isDone else { return }
        update(slot) { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[index].isDone = !isDone
        }
    }

    @discardableResult
    func remove(_ id: UUID, in slot: PlanSlot) -> Bool {
        update(slot) { tasks in
            tasks.removeAll(where: { $0.id == id })
        }
    }

    func saveNote(_ text: String, for day: String) -> Bool {
        save { $0[noteFor: day] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
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
        guard let isDone = plan.deadlineItems.first(where: { $0.id == id })?.isDone else { return }
        _ = updateDeadlines { deadlines in
            guard let index = deadlines.firstIndex(where: { $0.id == id }) else { return }
            deadlines[index].isDone = !isDone
        }
    }

    func removeDeadline(_ id: UUID) -> Bool {
        updateDeadlines { $0.removeAll { $0.id == id } }
    }

    private func updateDeadlines(_ change: (inout [PlanDeadline]) -> Void) -> Bool {
        save { change(&$0.deadlineItems) }
    }

    @discardableResult
    private func update(_ slot: PlanSlot, _ change: (inout [PlanTask]) -> Void) -> Bool {
        save { change(&$0[slot]) }
    }

    private func save(_ change: (inout Plan) -> Void) -> Bool {
        guard isReady else { return false }
        do {
            let disk = try disk()
            try disk.withWriteLock {
                let latest = try disk.read()
                var updated = latest
                change(&updated)
                if updated != latest { try disk.write(updated) }
                if plan != updated { plan = updated }
                if updated != latest { planDidChange(updated) }
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存失败。请检查本机计划文件和磁盘空间后重试。"
            return false
        }
    }
}
