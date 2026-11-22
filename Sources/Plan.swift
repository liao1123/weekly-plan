import Combine
import Darwin
import Foundation

enum PlanSlot: Equatable {
    case goal(String)
    case day(String)
}

enum PlanTaskStatus: Equatable {
    case pending
    case completed
    case incomplete

    var next: Self {
        switch self {
        case .pending: .completed
        case .completed: .incomplete
        case .incomplete: .pending
        }
    }
}

struct PlanTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var isDone = false
    var markedIncomplete: Bool?

    var status: PlanTaskStatus {
        get { isDone ? .completed : markedIncomplete == true ? .incomplete : .pending }
        set {
            isDone = newValue == .completed
            markedIncomplete = newValue == .incomplete ? true : nil
        }
    }
}

struct PlanDeadline: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var dueAt: Date
    var isDone = false
    var countdownEnabled: Bool?
    var link: URL?

    // Deadlines saved before this setting was introduced still count down.
    var showsCountdown: Bool { countdownEnabled ?? true }

    var dateLabel: String {
        dueAt.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    static func webLink(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = parts.host, !host.isEmpty else { return nil }
        return parts.url
    }
}

enum IdeaStatus: String, Codable, CaseIterable {
    case pending
    case testing
    case verified

    var label: String {
        switch self {
        case .pending: "待验证"
        case .testing: "验证中"
        case .verified: "已验证"
        }
    }
}

struct PlanIdea: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    var title: String
    var status: IdeaStatus = .pending
    var verificationPlan = ""
    var verificationResult = ""

    init(title: String) {
        id = UUID()
        createdAt = .now
        self.title = title
    }
}

struct DeadlineCountdown {
    let dueAt: Date
    let now: Date

    var isOverdue: Bool { now >= dueAt }
    var statusLabel: String { isOverdue ? "已超时" : "还剩" }
    var label: String { "\(statusLabel) \(durationLabel)" }

    var durationLabel: String {
        let remaining = dueAt.timeIntervalSince(now)
        let seconds = Int(isOverdue ? floor(-remaining) : ceil(remaining))
        let days = seconds / 86_400
        let clock = String(format: "%02d:%02d:%02d", seconds / 3_600 % 24, seconds / 60 % 60, seconds % 60)
        return days > 0 ? "\(days)天 \(clock)" : clock
    }
}

struct Plan: Codable, Equatable {
    private var goals: [String: [PlanTask]] = [:]
    private var days: [String: [PlanTask]] = [:]
    // Keep notes from older versions when saving the plan.
    private var notes: [String: String]?
    private var deadlines: [PlanDeadline]?
    private var ideas: [PlanIdea]?

    var deadlineItems: [PlanDeadline] {
        get { deadlines ?? [] }
        set { deadlines = newValue.isEmpty ? nil : newValue }
    }

    var orderedDeadlines: [PlanDeadline] {
        deadlineItems.sorted {
            if $0.isDone != $1.isDone { return !$0.isDone }
            return $0.dueAt < $1.dueAt
        }
    }

    var ideaItems: [PlanIdea] {
        get { ideas ?? [] }
        set { ideas = newValue.isEmpty ? nil : newValue }
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
        guard let isDone = plan[slot].first(where: { $0.id == id })?.isDone else { return }
        updateStatus(id, in: slot) { _ in isDone ? .pending : .completed }
    }

    func cycleStatus(_ id: UUID, in slot: PlanSlot) {
        updateStatus(id, in: slot) { $0.next }
    }

    private func updateStatus(_ id: UUID, in slot: PlanSlot, next: (PlanTaskStatus) -> PlanTaskStatus) {
        update(slot) { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[index].status = next(tasks[index].status)
        }
    }

    @discardableResult
    func remove(_ id: UUID, in slot: PlanSlot) -> Bool {
        update(slot) { tasks in
            tasks.removeAll(where: { $0.id == id })
        }
    }

    func saveDeadline(
        _ text: String, dueAt: Date, showsCountdown: Bool, link: URL? = nil, editing id: UUID?
    ) -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        if let link, PlanDeadline.webLink(link.absoluteString) == nil { return false }
        let minute = Calendar.current.dateInterval(of: .minute, for: dueAt)?.start ?? dueAt
        return updateDeadlines { deadlines in
            if let id {
                guard let index = deadlines.firstIndex(where: { $0.id == id }) else { return }
                deadlines[index].title = title
                deadlines[index].dueAt = minute
                deadlines[index].countdownEnabled = showsCountdown
                deadlines[index].link = link
            } else {
                deadlines.append(PlanDeadline(
                    title: title, dueAt: minute, countdownEnabled: showsCountdown, link: link
                ))
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

    func addIdea(_ text: String) -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let idea = PlanIdea(title: title)
        return save { $0.ideaItems.append(idea) }
    }

    func saveIdea(_ idea: PlanIdea, replacing original: PlanIdea) -> Bool {
        var updated = idea
        updated.title = idea.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty, updated.id == original.id else { return false }

        var changedElsewhere = false
        let saved = save { plan in
            guard let index = plan.ideaItems.firstIndex(where: { $0.id == idea.id }),
                  plan.ideaItems[index] == original else {
                changedElsewhere = true
                return
            }
            plan.ideaItems[index] = updated
        }
        if changedElsewhere {
            errorMessage = "这条 Idea 已更新或删除。请取消编辑后重新打开。"
        }
        return saved && !changedElsewhere
    }

    func removeIdea(_ id: UUID) -> Bool {
        save { $0.ideaItems.removeAll { $0.id == id } }
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
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存失败。请检查本机计划文件和磁盘空间后重试。"
            return false
        }
    }
}
