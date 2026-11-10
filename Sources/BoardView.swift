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
    @State private var dailyWidth: CGFloat = 522
    @GestureState private var dateColumnDrag: CGFloat?
    @AppStorage("WeekPlanDateColumnShare") private var dateColumnShare = 0.07

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
                        .font(.system(size: 13))
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(calendar.weekTitle(from: weekStart, to: dates[6]))
                    .font(.system(size: 13))
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
                    .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 13, weight: .medium))
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
        let savedWidth = DateColumnWidth(available: dailyWidth, share: dateColumnShare)
        let dateWidth = savedWidth.adjusting(by: dateColumnDrag ?? 0).width
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("日期")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 10)
                    .frame(width: dateWidth, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                sectionTitle("每日安排", icon: "list.bullet", tasks: tasks)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }

            VStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    if date != weekStart { rule }
                    dayRow(date, dateWidth: dateWidth).id(calendar.dayKey(date))
                }
            }
            .modifier(BoardCard(palette: palette))
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { dailyWidth = $0 }
        .overlay(alignment: .leading) {
            dateDivider(savedWidth: savedWidth, dateWidth: dateWidth)
                .offset(x: dateWidth - ColumnResizeHandle.hitWidth / 2)
        }
    }

    private func dateDivider(savedWidth: DateColumnWidth, dateWidth: CGFloat) -> some View {
        ColumnResizeHandle(palette: palette, dragging: dateColumnDrag != nil)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($dateColumnDrag) { value, distance, _ in
                    distance = value.translation.width
                }
                .onEnded { value in
                    dateColumnShare = savedWidth.adjusting(by: value.translation.width).share
                }
        )
        .help("拖动调整列宽")
        .accessibilityLabel("日期列宽")
        .accessibilityValue("\(Int(dateWidth.rounded())) 点")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                dateColumnShare = savedWidth.adjusting(by: 12).share
            case .decrement:
                dateColumnShare = savedWidth.adjusting(by: -12).share
            @unknown default:
                break
            }
        }
    }

    private func sectionTitle(_ title: String, icon: String, tasks: [PlanTask]) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !tasks.isEmpty {
                Text("已完成 \(tasks.filter(\.isDone).count)/\(tasks.count)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private func dayRow(_ date: Date, dateWidth: CGFloat) -> some View {
        let key = calendar.dayKey(date)
        let isToday = key == calendar.dayKey(now)
        return HStack(alignment: .top, spacing: 0) {
            dayLabel(date, isToday: isToday)
                .frame(width: dateWidth, alignment: .leading)
            taskList(in: .day(key), addLabel: "为\(calendar.weekday(date))添加待办")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .frame(minHeight: 54, alignment: .topLeading)
        .background(alignment: .leading) {
            (isToday ? palette.blueWash : palette.subtle).frame(width: dateWidth)
        }
    }

    private func dayLabel(_ date: Date, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(calendar.weekday(date))
                    .font(.system(size: 12, weight: .medium))
                if isToday {
                    Text("今天")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .foregroundStyle(isToday ? palette.accent : palette.muted)
            Text(calendar.shortDate(date))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? palette.accent : palette.ink)
        }
        .padding(.leading, 10)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func taskList(in slot: PlanSlot, addLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(store.plan[slot]) { task in
                if let draft, draft.slot == slot, draft.taskID == task.id {
                    if draft.mode == .inline {
                        inlineEditor(draft, task: task)
                    } else {
                        editor(draft)
                    }
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
                    addSymbol
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

    private var addSymbol: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 22, height: 22)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(palette.line, lineWidth: 1)
            }
    }

    private func taskRow(_ task: PlanTask, slot: PlanSlot) -> some View {
        let write = { beginEditing(slot: slot, task: task, mode: .inline) }
        let editDetails = { beginEditing(slot: slot, task: task) }
        let clicks = TapGesture(count: 2).exclusively(before: TapGesture())
        return HStack(alignment: .top, spacing: 3) {
            taskStatusControl(task, slot: slot)

            Text(task.title)
                .font(.system(size: 15))
                .foregroundStyle(task.isDone ? palette.muted : palette.ink)
                .strikethrough(task.isDone)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(clicks.onEnded { click in
                    switch click {
                    case .first: editDetails()
                    case .second: write()
                    }
                })
                .focusable(interactions: .activate)
                .onKeyPress(keys: [.return, .space], phases: .down) { _ in
                    write()
                    return .handled
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { write() }
                .accessibilityAction(named: Text("详细编辑"), editDetails)
                .help("单击续写，双击详细编辑")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskStatusControl(_ task: PlanTask, slot: PlanSlot) -> some View {
        switch slot {
        case .day:
            let statusLabel = switch task.status {
            case .pending: "待办"
            case .completed: "已完成"
            case .incomplete: "未完成"
            }
            Button {
                store.cycleStatus(task.id, in: slot)
            } label: {
                taskMark(task.status, checkmarkColor: palette.success)
            }
            .help("点按切换待办状态")
            .accessibilityLabel("切换待办状态：\(task.title)")
            .accessibilityValue(statusLabel)
        case .goal:
            Button {
                store.toggle(task.id, in: slot)
            } label: {
                taskMark(task.isDone ? .completed : .pending, checkmarkColor: palette.accent)
            }
            .help(task.isDone ? "取消完成" : "标记完成")
            .accessibilityLabel(task.isDone ? "取消完成：\(task.title)" : "标记完成：\(task.title)")
        }
    }

    private func taskMark(_ status: PlanTaskStatus, checkmarkColor: Color) -> some View {
        let color = switch status {
        case .completed: checkmarkColor
        case .incomplete: palette.warning
        case .pending: palette.checkBorder
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color, lineWidth: 1)
                .frame(width: 17, height: 17)
            if status != .pending {
                Image(systemName: status == .completed ? "checkmark" : "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 28, height: 30)
        .contentShape(Rectangle())
    }

    private func inlineEditor(_ active: Draft, task: PlanTask) -> some View {
        HStack(alignment: .top, spacing: 3) {
            taskStatusControl(task, slot: active.slot)
            InlineTaskEditor(
                text: draftText(for: active),
                onSave: {
                    if draft?.id == active.id, draft?.mode == .inline { _ = finishEditing() }
                },
                onCancel: {
                    if draft?.id == active.id { draft = nil }
                },
                onDetails: {
                    if draft?.id == active.id { draft?.mode = .details }
                }
            )
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(palette.accent.opacity(0.65), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .help("回车保存，双击详细编辑")
        }
        .buttonStyle(.plain)
        .id(active.id)
    }

    private func draftText(for active: Draft) -> Binding<String> {
        Binding(
            get: { draft?.id == active.id ? draft?.text ?? active.text : active.text },
            set: { if draft?.id == active.id { draft?.text = $0 } }
        )
    }

    private func editor(_ active: Draft) -> some View {
        DraftEditor(
            text: draftText(for: active),
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

    private func beginEditing(slot: PlanSlot, task: PlanTask?, mode: Draft.Mode = .details) {
        guard store.isReady, finishEditing() else { return }
        draft = Draft(slot: slot, taskID: task?.id, text: task?.title ?? "", mode: mode)
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
    enum Mode {
        case inline
        case details
    }

    let id = UUID()
    let slot: PlanSlot
    let taskID: UUID?
    var text: String
    var mode: Mode
}

private struct DateColumnWidth {
    private static let dateMinimum: CGFloat = 82
    private static let tasksMinimum: CGFloat = 210
    private let extra: CGFloat
    private(set) var share: Double

    init(available: CGFloat, share: Double) {
        extra = max(0, available - Self.dateMinimum - Self.tasksMinimum)
        self.share = min(max(0, share), 1)
    }

    var width: CGFloat { Self.dateMinimum + extra * CGFloat(share) }

    func adjusting(by distance: CGFloat) -> Self {
        guard extra > 0 else { return self }
        var result = self
        result.share = min(max(0, share + Double(distance / extra)), 1)
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
    let onSave: () -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
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
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("⌘↩ 保存")
            }
            .controlSize(.small)
            .font(.system(size: 13))
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
    var success: Color { color(0x15803D, 0x86EFAC) }
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
