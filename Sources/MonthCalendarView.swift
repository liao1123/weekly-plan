import SwiftUI

struct MonthCalendarView: View {
    @ObservedObject var store: PlanStore
    let openWeek: (Date) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var selected: Date
    @State private var today = Date.now

    private let calendar = PlanCalendar()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    init(store: PlanStore, initialDate: Date, openWeek: @escaping (Date) -> Void) {
        self.store = store
        self.openWeek = openWeek
        _selected = State(initialValue: initialDate)
    }

    private var palette: BoardPalette { BoardPalette(dark: scheme == .dark) }
    private var selectedKey: String { calendar.dayKey(selected) }
    private var monthTitle: String {
        let month = calendar.calendar.dateComponents([.year, .month], from: selected)
        return "\(month.year!)年\(month.month!)月"
    }

    var body: some View {
        let deadlinesByDay = Dictionary(grouping: store.plan.deadlineItems) { calendar.dayKey($0.dueAt) }
        VStack(alignment: .leading, spacing: 15) {
            header
            HStack(spacing: 14) {
                monthGrid(deadlinesByDay: deadlinesByDay)
                details(deadlines: deadlinesByDay[selectedKey, default: []])
                    .frame(width: 255)
            }
        }
        .padding(18)
        .background(palette.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = .now }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("月历")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.muted)
                Text(monthTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            HStack(spacing: 7) {
                Text("跳到日期")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
                DatePicker("跳到日期", selection: $selected, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
            HStack(spacing: 2) {
                monthArrow("chevron.left", title: "上个月", offset: -1)
                Button { selected = .now; today = selected } label: {
                    Text("今天")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 5))
                }
                monthArrow("chevron.right", title: "下个月", offset: 1)
            }
            .buttonStyle(.plain)
            .padding(3)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(palette.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func monthArrow(_ symbol: String, title: String, offset: Int) -> some View {
        Button {
            if let date = calendar.calendar.date(byAdding: .month, value: offset, to: selected) {
                selected = date
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.muted)
                .frame(width: 27, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .help(title)
    }

    private func monthGrid(deadlinesByDay: [String: [PlanDeadline]]) -> some View {
        let days = calendar.monthGridDates(for: selected)
        let rowCount = days.count / weekdays.count
        return GeometryReader { geometry in
            let headerHeight: CGFloat = 30
            let rowHeight = max(44, (geometry.size.height - headerHeight - CGFloat(rowCount)) / CGFloat(rowCount))
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: headerHeight)
                            .background(palette.subtle)
                    }
                }
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(days, id: \.self) { date in
                        let key = calendar.dayKey(date)
                        dayCell(date, key: key, deadlines: deadlinesByDay[key, default: []].count, height: rowHeight)
                    }
                }
            }
            .background(palette.line)
            .modifier(BoardCard(palette: palette))
        }
    }

    private func dayCell(_ date: Date, key: String, deadlines: Int, height: CGFloat) -> some View {
        let tasks = store.plan[.day(key)].count
        let hasNote = !store.plan[noteFor: key].isEmpty
        let inMonth = calendar.calendar.isDate(date, equalTo: selected, toGranularity: .month)
        let isSelected = key == selectedKey
        let isToday = key == calendar.dayKey(today)

        return Button { selected = date } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(calendar.calendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isToday || isSelected ? palette.accent : inMonth ? palette.ink : palette.muted)
                    if isToday {
                        Circle().fill(palette.accent).frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                    if hasNote {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.muted)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    if tasks > 0 {
                        Label("\(tasks)", systemImage: "checklist")
                            .foregroundStyle(palette.accent)
                    }
                    if deadlines > 0 {
                        Label("\(deadlines)", systemImage: "clock")
                            .foregroundStyle(palette.warning)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .topLeading)
            .background(isSelected ? palette.blueWash : inMonth ? palette.surface : palette.subtle)
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(palette.accent.opacity(0.72), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.shortDate(date)) \(calendar.weekday(date))")
        .accessibilityValue("\(tasks) 项待办，\(deadlines) 项 DDL\(hasNote ? "，有备注" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func details(deadlines: [PlanDeadline]) -> some View {
        let tasks = store.plan[.day(selectedKey)]
        let note = store.plan[noteFor: selectedKey]
        let goals = store.plan[.goal(calendar.dayKey(calendar.weekStart(for: selected)))]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(calendar.shortDate(selected))
                    .font(.system(size: 23, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(calendar.weekday(selected))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if !deadlines.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            section("DDL", icon: "clock")
                            ForEach(deadlines.sorted { $0.dueAt < $1.dueAt }) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .strikethrough(item.isDone)
                                        .foregroundStyle(item.isDone ? palette.muted : palette.ink)
                                    Text(item.dueAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))))
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.muted)
                                }
                            }
                        }
                    }
                    taskSection("当天待办", icon: "checklist", tasks: tasks)
                    if !note.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            section("备注 / 标记", icon: "note.text")
                            Text(note).foregroundStyle(palette.ink)
                        }
                    }
                    if !goals.isEmpty {
                        taskSection("所在周目标", icon: "flag", tasks: goals)
                    }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .id(selectedKey)
            Button { openWeek(selected) } label: {
                Label("打开所在周", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .modifier(BoardCard(palette: palette))
    }

    private func taskSection(_ title: String, icon: String, tasks: [PlanTask]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            section(title, icon: icon)
            if tasks.isEmpty {
                Text("暂无待办").foregroundStyle(palette.muted)
            }
            ForEach(tasks) { task in
                Label {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: task.isDone ? "checkmark.square" : "square")
                        .foregroundStyle(task.isDone ? palette.accent : palette.muted)
                }
                .foregroundStyle(task.isDone ? palette.muted : palette.ink)
            }
        }
    }

    private func section(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.accent)
            .accessibilityAddTraits(.isHeader)
    }
}
