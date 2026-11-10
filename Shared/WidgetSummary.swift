import Foundation

struct WidgetTaskSummary: Codable, Equatable {
    let title: String
    let isDone: Bool
}

struct WidgetTaskList: Codable, Equatable {
    var items: [WidgetTaskSummary] = []
    var count = 0
    var completed = 0
}

struct WidgetDaySummary: Codable, Equatable {
    var tasks = WidgetTaskList()
}

struct WidgetDeadlineSummary: Codable, Equatable {
    let title: String
    let dueAt: Date
    let countdownEnabled: Bool?

    var showsCountdown: Bool { countdownEnabled ?? true }
}

struct WidgetSummary: Codable, Equatable {
    static let kind = "WeekPlanOverview"
    static let storageDirectory = "local.woxi.weekplan"

    private static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "WeekPlanWidgetGroupIdentifier") as? String
    }

    static var isConfigured: Bool { groupIdentifier != nil }

    var goals: [String: WidgetTaskList] = [:]
    var days: [String: WidgetDaySummary] = [:]
    var deadline: WidgetDeadlineSummary?

    func write() throws {
        let file = try Self.snapshotFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    static func readFromExtension() throws -> WidgetSummary {
        try JSONDecoder().decode(WidgetSummary.self, from: Data(contentsOf: snapshotFile()))
    }

    private static func snapshotFile() throws -> URL {
        guard let groupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw CocoaError(.fileReadNoPermission)
        }
        return container.appending(path: "WidgetSnapshot.json")
    }
}
