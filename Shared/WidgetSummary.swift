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
    var note: String?
}

struct WidgetDeadlineSummary: Codable, Equatable {
    let title: String
    let dueAt: Date
}

struct WidgetSummary: Codable, Equatable {
    static let kind = "WeekPlanOverview"
    static let storageDirectory = "local.woxi.weekplan"
    private static let fileName = "WidgetSnapshot.json"

    var goals: [String: WidgetTaskList] = [:]
    var days: [String: WidgetDaySummary] = [:]
    var deadline: WidgetDeadlineSummary?

    func write() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let file = Self.file(in: support)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    static func readFromExtension() throws -> WidgetSummary {
        // The WidgetKit process has a separate sandbox home.
        guard let home = FileManager.default.homeDirectory(forUser: NSUserName()) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let file = file(in: home.appending(path: "Library/Application Support"))
        return try JSONDecoder().decode(WidgetSummary.self, from: Data(contentsOf: file))
    }

    private static func file(in applicationSupport: URL) -> URL {
        applicationSupport.appending(path: storageDirectory).appending(path: fileName)
    }
}
