import SwiftUI

struct DeadlineBar: View {
    @ObservedObject var store: PlanStore
    let palette: BoardPalette

    @State private var page: DeadlinePage?

    var body: some View {
        HStack(spacing: 9) {
            Label("DDL", systemImage: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityAddTraits(.isHeader)

            if let deadline = store.plan.firstOpenDeadline {
                Button {
                    open(deadline)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deadline.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(deadline.dateLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .help("编辑截止时间")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let time = DeadlineCountdown(dueAt: deadline.dueAt, now: context.date)
                    Text(time.label)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(time.isOverdue ? palette.warning : palette.accent)
                        .fixedSize()
                }
            } else {
                Text(store.plan.deadlineItems.isEmpty ? "记录会议、交稿和长期待办的时间" : "暂无未完成的 DDL")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !store.plan.deadlineItems.isEmpty {
                control("ellipsis", title: "查看全部 DDL") {
                    page = .list
                }
            }
            control("plus", title: "添加 DDL") { open() }
        }
        .buttonStyle(.plain)
        .padding(9)
        .modifier(BoardCard(palette: palette))
        .popover(item: $page, arrowEdge: .bottom) { presented in
            VStack(alignment: .leading, spacing: 12) {
                switch presented {
                case .list:
                    deadlineList
                case .editor(let draft):
                    DeadlineForm(draft: draft, store: store, palette: palette) { page = nil }
                }
                if let message = store.errorMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.warning)
                }
            }
            .padding(14)
            .frame(width: 340)
            .onExitCommand { page = nil }
        }
    }

    private func control(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .help(title)
    }

    private func open(_ deadline: PlanDeadline? = nil) {
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        page = .editor(DeadlineDraft(id: deadline?.id, title: deadline?.title ?? "", dueAt: deadline?.dueAt ?? nextHour))
    }

    private var deadlineList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("全部 DDL").font(.headline)
                Spacer()
                control("plus", title: "添加 DDL") { open() }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.plan.deadlineItems.sorted(by: { $0.dueAt < $1.dueAt })) { deadline in
                        HStack(spacing: 9) {
                            Button { store.toggleDeadline(deadline.id) } label: {
                                Image(systemName: deadline.isDone ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 15))
                                    .foregroundStyle(deadline.isDone ? palette.accent : palette.muted)
                            }
                            .accessibilityLabel(deadline.isDone ? "恢复 \(deadline.title)" : "完成 \(deadline.title)")
                            Button { open(deadline) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(deadline.title)
                                        .strikethrough(deadline.isDone)
                                        .lineLimit(2)
                                    Text(deadline.dateLabel)
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 260)
        }
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
            Text(draft.id == nil ? "添加 DDL" : "编辑 DDL")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("会议、交稿或长期待办", text: $draft.title)
                .accessibilityLabel("事项名称")
                .focused($titleFocused)
            DatePicker("截止时间", selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            HStack {
                if let id = draft.id {
                    Button("删除", role: .destructive) {
                        if store.removeDeadline(id) { close() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.warning)
                }
                Spacer()
                Button("取消", action: close)
                Button("保存") {
                    if store.saveDeadline(draft.title, dueAt: draft.dueAt, editing: draft.id) {
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

private enum DeadlinePage: Identifiable {
    case list
    case editor(DeadlineDraft)

    var id: String {
        switch self {
        case .list: "list"
        case .editor(let draft): draft.id?.uuidString ?? "new"
        }
    }
}

private struct DeadlineDraft {
    let id: UUID?
    var title: String
    var dueAt: Date
}
