import SwiftUI

struct DeadlineBar: View {
    @ObservedObject var store: PlanStore
    let palette: BoardPalette

    @State private var draft: DeadlineDraft?
    private let rowHeight: CGFloat = 42
    private let visibleRows = 3

    var body: some View {
        let deadlines = store.plan.orderedDeadlines
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 4) {
                Label("DDL", systemImage: "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityAddTraits(.isHeader)

                if deadlines.count > visibleRows {
                    Text("共 \(deadlines.count) 项")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.top, deadlines.isEmpty ? 0 : 5)

            if deadlines.isEmpty {
                Text("记录会议、交稿和长期待办的时间")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                deadlineList(deadlines)
            }

            Button {
                open()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 24, height: deadlines.isEmpty ? 30 : rowHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("添加 DDL")
            .help("添加 DDL")
        }
        .buttonStyle(.plain)
        .padding(9)
        .modifier(BoardCard(palette: palette))
        .popover(item: $draft, arrowEdge: .bottom) { presented in
            VStack(alignment: .leading, spacing: 12) {
                DeadlineForm(draft: presented, store: store, palette: palette) { draft = nil }
                if let message = store.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.warning)
                }
            }
            .padding(14)
            .frame(width: 340)
            .onExitCommand { draft = nil }
        }
    }

    private func open(_ deadline: PlanDeadline? = nil) {
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        draft = DeadlineDraft(
            deadlineID: deadline?.id,
            title: deadline?.title ?? "",
            dueAt: deadline?.dueAt ?? nextHour,
            showsCountdown: deadline?.showsCountdown ?? true
        )
    }

    @ViewBuilder
    private func deadlineList(_ deadlines: [PlanDeadline]) -> some View {
        let rows = VStack(spacing: 0) {
            ForEach(deadlines) { deadline in
                deadlineRow(deadline)
                    .overlay(alignment: .bottom) {
                        if deadline.id != deadlines.last?.id {
                            Rectangle().fill(palette.line).frame(height: 1)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }

        if deadlines.count > visibleRows {
            ScrollView { rows }
                .frame(height: rowHeight * CGFloat(visibleRows))
        } else {
            rows
        }
    }

    private func deadlineRow(_ deadline: PlanDeadline) -> some View {
        HStack(spacing: 6) {
            Button { store.toggleDeadline(deadline.id) } label: {
                Image(systemName: deadline.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(deadline.isDone ? palette.accent : palette.muted)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(deadline.isDone ? "恢复 \(deadline.title)" : "完成 \(deadline.title)")
            .help(deadline.isDone ? "取消完成" : "标记完成")

            Button { open(deadline) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(deadline.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(deadline.isDone ? palette.muted : palette.ink)
                        .strikethrough(deadline.isDone)
                        .lineLimit(1)
                    Text(deadline.dateLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .help("编辑截止时间")

            if deadline.showsCountdown && !deadline.isDone {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let time = DeadlineCountdown(dueAt: deadline.dueAt, now: context.date)
                    Text(time.label)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(time.isOverdue ? palette.warning : palette.accent)
                        .fixedSize()
                }
            }
        }
        .frame(height: rowHeight)
    }
}

private struct DeadlineForm: View {
    @State var draft: DeadlineDraft
    let store: PlanStore
    let palette: BoardPalette
    let close: () -> Void
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.deadlineID == nil ? "添加 DDL" : "编辑 DDL")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("会议、交稿或长期待办", text: $draft.title)
                .font(.system(size: 14))
                .accessibilityLabel("事项名称")
                .focused($titleFocused)
            DatePicker("截止时间", selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            Toggle("显示倒计时", isOn: $draft.showsCountdown)
            HStack {
                if let id = draft.deadlineID {
                    Button("删除", role: .destructive) {
                        if store.removeDeadline(id) { close() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.warning)
                }
                Spacer()
                Button("取消", action: close)
                Button("保存") {
                    if store.saveDeadline(
                        draft.title,
                        dueAt: draft.dueAt,
                        showsCountdown: draft.showsCountdown,
                        editing: draft.deadlineID
                    ) {
                        close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
        .onAppear { titleFocused = true }
    }
}

private struct DeadlineDraft: Identifiable {
    let id = UUID()
    let deadlineID: UUID?
    var title: String
    var dueAt: Date
    var showsCountdown: Bool
}
