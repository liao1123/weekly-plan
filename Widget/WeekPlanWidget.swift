import OSLog
import SwiftUI
import WidgetKit

@main
struct WeekPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummary.kind, provider: WeekPlanProvider()) { entry in
            WeekPlanWidgetView(entry: entry)
        }
        .configurationDisplayName("周计划")
        .description("在桌面查看 DDL、本周目标和今日待办。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct WeekPlanEntry: TimelineEntry {
    let date: Date
    let dateLabel: String
    let goals: WidgetTaskList
    let day: WidgetDaySummary
    let deadline: WidgetDeadlineSummary?
    let isReady: Bool
}

private struct WeekPlanProvider: TimelineProvider {
    private let calendar = PlanCalendar()
    private let logger = Logger(subsystem: WidgetSummary.storageDirectory, category: "Widget")

    func placeholder(in context: Context) -> WeekPlanEntry {
        let now = Date.now
        let week = calendar.dayKey(calendar.weekStart(for: now))
        let goal = WidgetTaskSummary(title: "整理本周重点", isDone: false)
        let task = WidgetTaskSummary(title: "核对今天的安排", isDone: false)
        let sample = WidgetSummary(
            goals: [week: WidgetTaskList(items: [goal], count: 1)],
            days: [calendar.dayKey(now): WidgetDaySummary(
                tasks: WidgetTaskList(items: [task], count: 1)
            )],
            deadline: WidgetDeadlineSummary(title: "交稿", dueAt: now.addingTimeInterval(28_800), countdownEnabled: true)
        )
        return entry(at: now, summary: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekPlanEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now, summary: readSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekPlanEntry>) -> Void) {
        let now = Date.now
        guard WidgetSummary.isConfigured else {
            completion(Timeline(entries: [entry(at: now, summary: nil)], policy: .never))
            return
        }
        guard let summary = readSummary() else {
            let retry = now.addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry(at: now, summary: nil)], policy: .after(retry)))
            return
        }
        let midnight = calendar.calendar.startOfDay(for: now)
        var dates = [now] + (1...7).compactMap {
            calendar.calendar.date(byAdding: .day, value: $0, to: midnight)
        }
        if let deadline = summary.deadline, deadline.showsCountdown,
           deadline.dueAt > now, deadline.dueAt < (dates.last ?? now) {
            dates.append(deadline.dueAt)
        }
        let entries = dates.sorted().map { entry(at: $0, summary: summary) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func readSummary() -> WidgetSummary? {
        guard WidgetSummary.isConfigured else { return nil }
        do {
            let summary = try WidgetSummary.readFromExtension()
            logger.info("Loaded the local widget summary")
            return summary
        } catch {
            let failure = error as NSError
            logger.error("Could not read the local widget summary (\(failure.domain, privacy: .public) \(failure.code))")
            return nil
        }
    }

    private func entry(at date: Date, summary: WidgetSummary?) -> WeekPlanEntry {
        let week = calendar.dayKey(calendar.weekStart(for: date))
        return WeekPlanEntry(
            date: date,
            dateLabel: "\(calendar.shortDate(date)) · \(calendar.weekday(date))",
            goals: summary?.goals[week] ?? WidgetTaskList(),
            day: summary?.days[calendar.dayKey(date)] ?? WidgetDaySummary(),
            deadline: summary?.deadline,
            isReady: summary != nil
        )
    }
}

private struct WeekPlanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeekPlanEntry
    private var medium: Bool { family == .systemMedium }

    var body: some View {
        VStack(alignment: .leading, spacing: medium ? 6 : 11) {
            HStack {
                Label("周计划", systemImage: "calendar")
                    .font(.system(size: medium ? 14 : 17, weight: .semibold))
                    .widgetAccentable()
                Spacer(minLength: 3)
                Text(entry.dateLabel)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let deadline = entry.deadline {
                deadlineRow(deadline)
            }
            if entry.isReady {
                sections
            } else {
                Text(WidgetSummary.isConfigured ? "暂未加载安排，点按打开周计划" : "预览版未配置小组件数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func deadlineRow(_ item: WidgetDeadlineSummary) -> some View {
        HStack(spacing: 5) {
            Text("DDL").fontWeight(.bold)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 2)
            if !item.showsCountdown {
                Text(item.dueAt, format: .dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else if item.dueAt > entry.date {
                Text(timerInterval: entry.date...item.dueAt, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
            } else {
                Text("已超时")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: medium ? 11 : 12, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, medium ? 4 : 5)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7))
        .privacySensitive()
    }

    @ViewBuilder
    private var sections: some View {
        if medium {
            HStack(alignment: .top, spacing: 12) {
                taskSection("本周目标", list: entry.goals, limit: 1)
                taskSection("今日待办", list: entry.day.tasks, limit: 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                taskSection("本周目标", list: entry.goals, limit: 2)
                Divider()
                taskSection("今日待办", list: entry.day.tasks, limit: 4)
            }
        }
    }

    private func taskSection(_ title: String, list: WidgetTaskList, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: medium ? 3 : 6) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 2)
                if list.count > 0 {
                    Text("\(list.completed)/\(list.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: medium ? 11 : 12))
            if list.items.isEmpty {
                Text("暂无安排")
                    .font(.system(size: medium ? 11 : 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(list.items.prefix(limit).enumerated()), id: \.offset) { _, task in
                Label {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .lineLimit(medium ? 1 : 2)
                        .privacySensitive()
                } icon: {
                    Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                        .font(.system(size: medium ? 10 : 11))
                }
                .font(.system(size: medium ? 11 : 13))
                .foregroundStyle(task.isDone ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
