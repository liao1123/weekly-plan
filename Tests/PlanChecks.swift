import Foundation

@main
@MainActor
struct QA {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try verify(in: folder)
    }

    static func verify(in folder: URL) throws {
        let shanghai = PlanCalendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let iso = ISO8601DateFormatter()
        let tuesday = iso.date(from: "2026-11-10T03:00:00Z")!
        let key = shanghai.dayKey(shanghai.weekStart(for: tuesday))
        precondition(key == "2026-11-09")
        precondition(shanghai.weekday(tuesday) == "周二")
        precondition(shanghai.dates(inWeekOf: tuesday).map(shanghai.dayKey) == [
            "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"
        ])
        precondition(shanghai.dayKey(shanghai.week(from: tuesday, offset: 1)) == "2026-11-16")
        precondition(shanghai.dayKey(shanghai.week(from: tuesday, offset: -1)) == "2026-11-02")
        let yearEnd = iso.date(from: "2026-12-31T04:00:00Z")!
        let yearEndDays = shanghai.dates(inWeekOf: yearEnd)
        precondition(shanghai.weekTitle(from: yearEndDays[0], to: yearEndDays[6]) == "2026年 12.28 – 2027年 1.3")
        let newYork = PlanCalendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let dstSunday = iso.date(from: "2026-03-08T18:00:00Z")!
        precondition(newYork.dayKey(newYork.week(from: dstSunday, offset: 1)) == "2026-03-09")
        precondition(newYork.dates(inWeekOf: dstSunday).last.map(newYork.dayKey) == "2026-03-08")
        let november = shanghai.monthGridDates(for: tuesday).map(shanghai.dayKey)
        precondition(november.count == 42)
        precondition(november.first == "2026-10-26" && november.last == "2026-12-06")
        let february = iso.date(from: "2027-02-15T04:00:00Z")!
        precondition(shanghai.monthGridDates(for: february).count == 28)
        let dstMonth = newYork.monthGridDates(for: dstSunday).map(newYork.dayKey)
        precondition(dstMonth.count == 42 && Set(dstMonth).count == 42 && dstMonth.contains("2026-03-08"))

        let disk = PlanDisk(file: folder.appending(path: "plan.json"))
        let goal = PlanSlot.goal(key)
        let monday = PlanSlot.day(key)
        let day = PlanSlot.day("2026-11-10")
        var simulateFailure = false
        let store = PlanStore(disk: {
            if simulateFailure { throw CocoaError(.fileWriteNoPermission) }
            return disk
        })
        precondition(store.isReady && store.plan[goal].isEmpty)
        precondition(!store.save(" \n ", in: day, editing: nil))
        precondition(store.save(" 汇总进展 ", in: goal, editing: nil))
        precondition(store.save("整理本周资料", in: monday, editing: nil))
        precondition(store.save("  核对安排\n确认交付时间  ", in: day, editing: nil))
        let taskID = store.plan[day][0].id
        let updated = "核对安排与交付时间\n确认后更新记录"
        store.toggle(taskID, in: day)
        precondition(store.save(updated, in: day, editing: taskID))
        let reloaded = PlanStore(disk: { disk })
        precondition(reloaded.plan == store.plan)
        precondition(reloaded.plan[day] == [PlanTask(id: taskID, title: updated, isDone: true)])
        precondition(reloaded.plan[goal][0].title == "汇总进展")
        precondition(reloaded.plan[monday][0].title == "整理本周资料")
        precondition(reloaded.plan[.goal("2026-11-16")].isEmpty)
        let bytesWithoutNotes = try Data(contentsOf: disk.file)
        var legacyDocument = try JSONSerialization.jsonObject(with: bytesWithoutNotes) as! [String: Any]
        precondition(legacyDocument["notes"] == nil)
        let legacyNotes = ["2026-11-10": "待跟进\n周五核对", "2026-11-11": "已确认"]
        legacyDocument["notes"] = legacyNotes
        try JSONSerialization.data(withJSONObject: legacyDocument).write(to: disk.file, options: .atomic)
        store.load()
        let withNotes = try disk.read()
        precondition(withNotes[day] == reloaded.plan[day] && withNotes[goal] == reloaded.plan[goal])
        precondition(withNotes.deadlineItems.isEmpty)

        simulateFailure = true
        precondition(!store.remove(taskID, in: day))
        precondition(store.plan[day].count == 1 && store.errorMessage != nil)
        let stillSaved = try disk.read()
        precondition(stillSaved == withNotes && store.plan == withNotes)
        simulateFailure = false
        precondition(store.remove(taskID, in: day))
        let afterDelete = try disk.read()
        precondition(afterDelete[day].isEmpty && afterDelete[goal].count == 1)

        let mondayTask = afterDelete[monday][0]
        precondition(mondayTask.status == .pending && reloaded.plan[day][0].status == .completed)
        store.cycleStatus(mondayTask.id, in: monday)
        let completedPlan = try disk.read()
        precondition(completedPlan[monday][0].status == .completed && completedPlan[monday][0].isDone)
        store.cycleStatus(mondayTask.id, in: monday)
        let markedPlan = try disk.read()
        precondition(markedPlan[monday][0].status == .incomplete && !markedPlan[monday][0].isDone)
        store.cycleStatus(mondayTask.id, in: monday)
        let clearedPlan = try disk.read()
        precondition(clearedPlan == afterDelete)

        let later = tuesday.addingTimeInterval(86_400 + 7_200 + 180 + 4)
        precondition(DeadlineCountdown(dueAt: later, now: tuesday).label == "还剩 1天 02:03:04")
        precondition(DeadlineCountdown(dueAt: tuesday, now: tuesday.addingTimeInterval(63)).label == "已超时 00:01:03")
        precondition(!store.saveDeadline(" ", dueAt: later, showsCountdown: true, editing: nil))
        precondition(store.saveDeadline("长期稿件", dueAt: later, showsCountdown: false, editing: nil))
        precondition(store.saveDeadline(" 会议 ", dueAt: tuesday, showsCountdown: true, editing: nil))
        let meeting = store.plan.orderedDeadlines[0]
        precondition(meeting.title == "会议" && meeting.dueAt == tuesday && meeting.showsCountdown)
        store.toggleDeadline(meeting.id)
        precondition(store.plan.orderedDeadlines.first?.showsCountdown == false)
        precondition(store.plan.orderedDeadlines.map(\.title) == ["长期稿件", "会议"])
        precondition(store.saveDeadline("会议纪要", dueAt: tuesday.addingTimeInterval(73), showsCountdown: false, editing: meeting.id))
        let savedPlan = try disk.read()
        let savedMeeting = savedPlan.deadlineItems.first { $0.id == meeting.id }
        precondition(savedMeeting?.title == "会议纪要" && savedMeeting?.isDone == true)
        precondition(savedMeeting?.dueAt == tuesday.addingTimeInterval(60) && savedMeeting?.showsCountdown == false)
        let savedBytes = try Data(contentsOf: disk.file)
        let savedDocument = try JSONSerialization.jsonObject(with: savedBytes) as! [String: Any]
        precondition(savedDocument["notes"] as? [String: String] == legacyNotes)
        precondition(savedPlan[goal] == afterDelete[goal])

        var oldDocument = savedDocument
        oldDocument["deadlines"] = (savedDocument["deadlines"] as! [[String: Any]]).map { deadline in
            deadline.filter { $0.key != "countdownEnabled" }
        }
        let oldPlan = try JSONDecoder().decode(Plan.self, from: JSONSerialization.data(withJSONObject: oldDocument))
        precondition(oldPlan.deadlineItems.count == 2 && oldPlan.deadlineItems.allSatisfy(\.showsCountdown))
        precondition(store.removeDeadline(meeting.id))
        precondition(store.plan.deadlineItems.count == 1)

        let invalid = Data("corrupt".utf8)
        try invalid.write(to: disk.file, options: .atomic)
        let corrupted = PlanStore(disk: { disk })
        precondition(!corrupted.isReady)
        precondition(!corrupted.save("不可覆盖已有文件", in: day, editing: nil))
        let bytes = try Data(contentsOf: disk.file)
        precondition(bytes == invalid)

        let sharedDisk = PlanDisk(file: folder.appending(path: "multi-instance.json"))
        let first = PlanStore(disk: { sharedDisk })
        let second = PlanStore(disk: { sharedDisk })
        precondition(first.save("甲的待办", in: day, editing: nil))
        precondition(second.save("乙的待办", in: day, editing: nil))
        precondition(second.saveDeadline("交稿", dueAt: later, showsCountdown: true, editing: nil))
        let sharedPlan = try sharedDisk.read()
        precondition(sharedPlan[day].map(\.title) == ["甲的待办", "乙的待办"])
        precondition(sharedPlan.orderedDeadlines.first?.title == "交稿")
        let sharedTaskID = sharedPlan[day][0].id
        first.toggle(sharedTaskID, in: day)
        second.toggle(sharedTaskID, in: day)
        let afterBothToggles = try sharedDisk.read()
        precondition(afterBothToggles[day][0].isDone)

        print("PASS: calendar, legacy plans, deadlines, and multi-instance saves")
    }
}
