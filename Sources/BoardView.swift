import AppKit
import Combine
import SwiftUI

struct BoardView: View {
    @ObservedObject var store: PlanStore
    @Environment(\.colorScheme) private var scheme
    @State private var now: Date
    @State private var selectedWeek: Date?
    @State private var dayJump: DayJump?
    @State private var calendarDate: Date?
    @State private var draft: Draft?
    @State private var noteDraft: NoteDraft?
    @State private var dailyWidth: CGFloat = 522
    @GestureState private var columnDrag: ColumnDrag?
    @AppStorage("WeekPlanDateColumnShare") private var dateColumnShare = 0.07
    @AppStorage("WeekPlanNoteColumnShare") private var noteColumnShare = 0.13

    private let calendar = PlanCalendar()
    private let midnight = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
    private let timeZoneChange = NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
    private let activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)

    init(store: PlanStore, now: Date = .now) {
        self.store = store
        _now = State(initialValue: now)
    }

    private var palette: BoardPalette { BoardPalette(dark: scheme == .dark) }
    private var dates: [Date] { calendar.dates(inWeekOf: selectedWeek ?? now) }
    private var weekStart: Date { calendar.weekStart(for: selectedWeek ?? now) }
    private var weekKey: String { calendar.dayKey(weekStart) }
    private var isCurrentWeek: Bool { weekKey == calendar.dayKey(calendar.weekStart(for: now)) }

    var body: some View {
        ZStack {
            // Keep the week view mounted so returning preserves its scroll position.
            weekBoard
                .opacity(calendarDate == nil ? 1 : 0)
                .disabled(calendarDate != nil)
                .allowsHitTesting(calendarDate == nil)
                .accessibilityHidden(calendarDate != nil)

            if let calendarDate {
                MonthCalendarView(
                    store: store,
                    initialDate: calendarDate,
                    goBack: { self.calendarDate = nil },
                    openWeek: jumpToDay
                )
            }
        }
        .background(palette.canvas)
        .onReceive(midnight) { _ in now = .now }
        .onReceive(timeZoneChange) { _ in now = .now }
        .onReceive(activation) { _ in now = .now }
    }

    private var weekBoard: some View {
        VStack(spacing: 0) {
            header
            DeadlineBar(store: store, palette: palette)
                .disabled(!store.isReady)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            if let message = store.errorMessage {
                HStack {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                    Spacer()
                    if !store.isReady {
                        Button("重试", action: store.load)
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(palette.warning)
                .padding(10)
                .background(palette.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        goals
                            .id("goals")
                        daily
                    }
                    .disabled(!store.isReady)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .defaultScrollAnchor(.top)
                .onChange(of: weekKey) { _, _ in
                    if let jump = dayJump, calendar.weekStart(for: jump.date) == weekStart {
                        proxy.scrollTo(calendar.dayKey(jump.date), anchor: .top)
                    } else {
                        proxy.scrollTo("goals", anchor: .top)
                    }
                }
                .onChange(of: dayJump?.id) { _, _ in
                    if let jump = dayJump {
                        proxy.scrollTo(calendar.dayKey(jump.date), anchor: .top)
                    }
                }
                .onChange(of: draft?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 38, height: 38)
                .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("周计划")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(calendar.weekTitle(from: weekStart, to: dates[6]))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)

            Button {
                guard finishEditing() else { return }
                calendarDate = dayJump?.date ?? selectedWeek ?? now
            } label: {
                Label("月历", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 32)
                    .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开月历")
            .help("查看整月安排")

            HStack(spacing: 2) {
                Button { moveWeek(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help("上一周")
                .accessibilityLabel("上一周")

                Button {
                    if finishEditing() {
                        dayJump = nil
                        selectedWeek = nil
                    }
                } label: {
                    Text("本周")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isCurrentWeek ? palette.accent : palette.ink)
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(
                            isCurrentWeek ? palette.blueWash : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                }
                .help("回到本周")

                Button { moveWeek(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help("下一周")
                .accessibilityLabel("下一周")
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.muted)
            .padding(2)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(palette.line, lineWidth: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 15)
    }

    private var goals: some View {
        let slot = PlanSlot.goal(weekKey)
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle("本周目标", icon: "flag", tasks: store.plan[slot])
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(palette.subtle)

            rule
            taskList(in: slot, addLabel: "添加周目标")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .modifier(BoardCard(palette: palette))
    }

    private var daily: some View {
        let tasks = dates.flatMap { store.plan[.day(calendar.dayKey($0))] }
        let savedWidths = DayColumnWidths(
            available: dailyWidth, dateShare: dateColumnShare, noteShare: noteColumnShare
        )
        let widths = columnDrag.map { savedWidths.adjusting($0.column, by: $0.distance) } ?? savedWidths
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("日期")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 10)
                    .frame(width: widths.date, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                sectionTitle("每日安排", icon: "list.bullet", tasks: tasks)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                Label("备注 / 标记", systemImage: "note.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 10)
                    .frame(width: widths.note, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    if date != weekStart { rule }
                    dayRow(date, widths: widths).id(calendar.dayKey(date))
                }
            }
            .modifier(BoardCard(palette: palette))
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { dailyWidth = $0 }
        .overlay(alignment: .leading) {
            columnDivider(.date, savedWidths: savedWidths, widths: widths)
                .offset(x: widths.date - ColumnResizeHandle.hitWidth / 2)
        }
        .overlay(alignment: .trailing) {
            columnDivider(.note, savedWidths: savedWidths, widths: widths)
                .offset(x: ColumnResizeHandle.hitWidth / 2 - widths.note)
        }
    }

    private func columnDivider(
        _ column: ResizableColumn, savedWidths: DayColumnWidths, widths: DayColumnWidths
    ) -> some View {
        ColumnResizeHandle(
            palette: palette, dragging: columnDrag?.column == column
        )
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($columnDrag) { value, drag, _ in
                    drag = ColumnDrag(column: column, distance: value.translation.width)
                }
                .onEnded { value in
                    saveColumnWidth(column, from: savedWidths.adjusting(column, by: value.translation.width))
                }
        )
        .help("拖动调整列宽")
        .accessibilityLabel(column == .date ? "日期列宽" : "备注列宽")
        .accessibilityValue("\(Int((column == .date ? widths.date : widths.note).rounded())) 点")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = column == .date ? 12 : -12
            switch direction {
            case .increment:
                saveColumnWidth(column, from: savedWidths.adjusting(column, by: step))
            case .decrement:
                saveColumnWidth(column, from: savedWidths.adjusting(column, by: -step))
            @unknown default:
                break
            }
        }
    }

    private func saveColumnWidth(_ column: ResizableColumn, from widths: DayColumnWidths) {
        switch column {
        case .date: dateColumnShare = widths.dateShare
        case .note: noteColumnShare = widths.noteShare
        }
    }

    private func sectionTitle(_ title: String, icon: String, tasks: [PlanTask]) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !tasks.isEmpty {
                Text("已完成 \(tasks.filter(\.isDone).count)/\(tasks.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private func dayRow(_ date: Date, widths: DayColumnWidths) -> some View {
        let key = calendar.dayKey(date)
        let isToday = key == calendar.dayKey(now)
        return HStack(alignment: .top, spacing: 0) {
            dayLabel(date, isToday: isToday)
                .frame(width: widths.date, alignment: .leading)
            taskList(in: .day(key), addLabel: "为\(calendar.weekday(date))添加待办")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            noteCell(for: key, weekday: calendar.weekday(date))
                .frame(width: widths.note, alignment: .leading)
        }
        .frame(minHeight: 50, alignment: .topLeading)
        .background(alignment: .leading) {
            (isToday ? palette.blueWash : palette.subtle).frame(width: widths.date)
        }
        .background(alignment: .trailing) {
            palette.subtle.frame(width: widths.note)
        }
    }

    private func dayLabel(_ date: Date, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(calendar.weekday(date))
                    .font(.system(size: 11, weight: .medium))
                if isToday {
                    Text("今天")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .foregroundStyle(isToday ? palette.accent : palette.muted)
            Text(calendar.shortDate(date))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? palette.accent : palette.ink)
        }
        .padding(.leading, 10)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func noteCell(for day: String, weekday: String) -> some View {
        let note = store.plan[noteFor: day]
        return Button {
            guard finishEditing() else { return }
            noteDraft = NoteDraft(day: day, text: note)
        } label: {
            Group {
                if note.isEmpty {
                    addSymbol(color: palette.muted)
                } else {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.isEmpty ? "\(weekday)添加备注" : "\(weekday)备注：\(note)")
        .help(note.isEmpty ? "添加备注或标记" : "编辑备注或标记")
        .popover(isPresented: Binding(
            get: { noteDraft?.day == day },
            set: { visible in
                if !visible, noteDraft?.day == day { noteDraft = nil }
            }
        ), arrowEdge: .trailing) {
            DraftEditor(
                text: Binding(get: { noteDraft?.text ?? "" }, set: { noteDraft?.text = $0 }),
                palette: palette,
                placeholder: "输入备注或标记",
                fieldLabel: "\(weekday)备注 / 标记",
                saveLabel: "保存",
                allowsEmpty: true,
                onSave: {
                    if let noteDraft, store.saveNote(noteDraft.text, for: day) { self.noteDraft = nil }
                },
                onCancel: { noteDraft = nil }
            )
            .padding(10)
            .frame(width: 276)
        }
    }

    @ViewBuilder
    private func taskList(in slot: PlanSlot, addLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(store.plan[slot]) { task in
                if let draft, draft.slot == slot, draft.taskID == task.id {
                    editor(draft)
                } else {
                    taskRow(task, slot: slot)
                }
            }

            if let draft, draft.slot == slot, draft.taskID == nil {
                editor(draft)
            } else {
                Button {
                    beginEditing(slot: slot, task: nil)
                } label: {
                    addSymbol(color: palette.accent)
                        .padding(.horizontal, 5)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(addLabel)
                .help(addLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addSymbol(color: Color) -> some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(palette.line, lineWidth: 1)
            }
    }

    private func taskRow(_ task: PlanTask, slot: PlanSlot) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Button {
                store.toggle(task.id, in: slot)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(task.isDone ? palette.accent : palette.checkBorder, lineWidth: 1)
                        .frame(width: 15, height: 15)
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .help(task.isDone ? "取消完成" : "标记完成")
            .accessibilityLabel(task.isDone ? "取消完成：\(task.title)" : "标记完成：\(task.title)")

            Button {
                beginEditing(slot: slot, task: task)
            } label: {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(task.isDone ? palette.muted : palette.ink)
                    .strikethrough(task.isDone)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .help("编辑任务")
            .contextMenu {
                Button("删除任务", role: .destructive) {
                    store.remove(task.id, in: slot)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func editor(_ active: Draft) -> some View {
        DraftEditor(
            text: Binding(get: { draft?.text ?? "" }, set: { draft?.text = $0 }),
            palette: palette,
            placeholder: "输入任务内容",
            fieldLabel: active.taskID == nil ? "新增任务" : "编辑任务",
            saveLabel: active.taskID == nil ? "添加" : "保存",
            onSave: { _ = finishEditing() },
            onCancel: { draft = nil },
            onDelete: active.taskID.map { id in
                { if store.remove(id, in: active.slot) { draft = nil } }
            }
        )
        .id(active.id)
    }

    private func moveWeek(_ offset: Int) {
        guard finishEditing() else { return }
        let target = calendar.week(from: weekStart, offset: offset)
        dayJump = nil
        selectedWeek = target == calendar.weekStart(for: now) ? nil : target
    }

    private func jumpToDay(_ date: Date) {
        guard finishEditing() else { return }
        let target = calendar.weekStart(for: date)
        selectedWeek = target == calendar.weekStart(for: now) ? nil : target
        dayJump = DayJump(date: date)
        calendarDate = nil
    }

    private func beginEditing(slot: PlanSlot, task: PlanTask?) {
        guard finishEditing() else { return }
        draft = Draft(slot: slot, taskID: task?.id, text: task?.title ?? "")
    }

    @discardableResult
    private func finishEditing() -> Bool {
        guard let draft else { return true }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, !store.save(text, in: draft.slot, editing: draft.taskID) {
            return false
        }
        self.draft = nil
        return true
    }

    private var rule: some View {
        Rectangle().fill(palette.line).frame(height: 1)
    }
}

private struct DayJump: Identifiable {
    let id = UUID()
    let date: Date
}

private struct Draft: Identifiable {
    let id = UUID()
    let slot: PlanSlot
    let taskID: UUID?
    var text: String
}

private struct NoteDraft {
    let day: String
    var text: String
}

private enum ResizableColumn {
    case date, note
}

private struct ColumnDrag {
    let column: ResizableColumn
    let distance: CGFloat
}

private struct DayColumnWidths {
    private static let dateMinimum: CGFloat = 68
    private static let tasksMinimum: CGFloat = 168
    private static let noteMinimum: CGFloat = 100
    private let extra: CGFloat
    private(set) var dateShare: Double
    private(set) var noteShare: Double

    init(available: CGFloat, dateShare: Double, noteShare: Double) {
        extra = max(0, available - Self.dateMinimum - Self.tasksMinimum - Self.noteMinimum)
        self.dateShare = min(max(0, dateShare), 1)
        self.noteShare = min(max(0, noteShare), 1 - self.dateShare)
    }

    var date: CGFloat { Self.dateMinimum + extra * CGFloat(dateShare) }
    var note: CGFloat { Self.noteMinimum + extra * CGFloat(noteShare) }

    func adjusting(_ column: ResizableColumn, by distance: CGFloat) -> Self {
        guard extra > 0 else { return self }
        let shift = Double(distance / extra)
        var result = self
        switch column {
        case .date: result.dateShare = min(max(0, dateShare + shift), 1 - noteShare)
        case .note: result.noteShare = min(max(0, noteShare - shift), 1 - dateShare)
        }
        return result
    }
}

private struct ColumnResizeHandle: View {
    static let hitWidth: CGFloat = 12
    let palette: BoardPalette
    let dragging: Bool
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || dragging ? palette.accent : palette.line)
            .frame(width: hovering || dragging ? 2 : 1)
            .frame(width: Self.hitWidth)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if !inside {
                    NSCursor.arrow.set()
                } else if #available(macOS 15.0, *) {
                    NSCursor.columnResize.set()
                } else {
                    NSCursor.resizeLeftRight.set()
                }
            }
    }
}

private struct DraftEditor: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    let palette: BoardPalette
    let placeholder: String
    let fieldLabel: String
    let saveLabel: String
    var allowsEmpty = false
    let onSave: () -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...6)
                .focused($focused)
                .foregroundStyle(palette.ink)
                .accessibilityLabel(fieldLabel)

            HStack(spacing: 10) {
                if let onDelete {
                    Button("删除", role: .destructive, action: onDelete)
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.warning)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.muted)
                Button(saveLabel, action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!allowsEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("⌘↩ 保存")
            }
            .controlSize(.small)
            .font(.system(size: 12))
        }
        .padding(8)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(palette.accent.opacity(0.65), lineWidth: 1)
        }
        .padding(.vertical, 3)
        .onAppear { focused = true }
        .onExitCommand(perform: onCancel)
    }
}

struct BoardCard: ViewModifier {
    let palette: BoardPalette

    func body(content: Content) -> some View {
        let border = RoundedRectangle(cornerRadius: 10)
        content
            .background(palette.surface)
            .clipShape(border)
            .overlay { border.strokeBorder(palette.line, lineWidth: 1) }
    }
}

struct BoardPalette {
    let dark: Bool
    var canvas: Color { color(0xF6F8FA, 0x1A1C21) }
    var surface: Color { color(0xFFFFFF, 0x202329) }
    var subtle: Color { color(0xFAFBFC, 0x252830) }
    var ink: Color { color(0x1F2329, 0xE8EBF0) }
    var muted: Color { color(0x646A73, 0xA8ADB7) }
    var line: Color { color(0xE1E5EB, 0x373B44) }
    var blueWash: Color { color(0xEAF1FF, 0x263454) }
    var accent: Color { color(0x245BDB, 0x91B2FF) }
    var checkBorder: Color { color(0x79818D, 0xA0A7B4) }
    var warning: Color { color(0xAB2828, 0xFFAAAA) }

    private func color(_ light: UInt32, _ darkValue: UInt32) -> Color {
        let hex = dark ? darkValue : light
        return Color(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}
