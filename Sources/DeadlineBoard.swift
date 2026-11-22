import SwiftUI

struct DeadlineBoard: View {
    @ObservedObject var store: PlanStore
    let palette: BoardPalette

    @State private var draft: DeadlineDraft?
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 14, alignment: .top)]

    var body: some View {
        let deadlines = store.plan.orderedDeadlines
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if !deadlines.isEmpty {
                    Text("共 \(deadlines.count) 项")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                addButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 9)

            if let message = store.errorMessage {
                HStack {
                    Label(message, systemImage: "exclamationmark.circle")
                    Spacer()
                    if !store.isReady {
                        Button("重试", action: store.load)
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(palette.warning)
                .padding(.horizontal, 18)
            }

            if deadlines.isEmpty, store.isReady {
                Text("暂无截止事项")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(deadlines) { deadline in
                            DeadlineCard(
                                deadline: deadline,
                                palette: palette,
                                edit: { open(deadline) },
                                toggle: { store.toggleDeadline(deadline.id) }
                            )
                        }
                    }
                    .disabled(!store.isReady)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
        .sheet(item: $draft) { presented in
            VStack(alignment: .leading, spacing: 12) {
                DeadlineForm(draft: presented, store: store, palette: palette) { draft = nil }
                if let message = store.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.warning)
                }
            }
            .padding(18)
            .frame(width: 360)
            .onExitCommand { draft = nil }
        }
    }

    private var addButton: some View {
        Button {
            open()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 32, height: 32)
                .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.isReady)
        .accessibilityLabel("添加 DDL")
        .help("添加 DDL")
    }

    private func open(_ deadline: PlanDeadline? = nil) {
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        draft = DeadlineDraft(
            deadlineID: deadline?.id,
            title: deadline?.title ?? "",
            dueAt: deadline?.dueAt ?? nextHour,
            showsCountdown: deadline?.showsCountdown ?? true,
            linkText: deadline?.link?.absoluteString ?? ""
        )
    }
}

private struct DeadlineCard: View {
    let deadline: PlanDeadline
    let palette: BoardPalette
    let edit: () -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: edit) {
                    Text(deadline.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(deadline.isDone ? palette.muted : palette.ink)
                        .strikethrough(deadline.isDone)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑 \(deadline.title)")
                .help(deadline.title)

                VStack(spacing: 4) {
                    Button(action: toggle) {
                        Image(systemName: deadline.isDone ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(deadline.isDone ? palette.success : palette.checkBorder)
                            .frame(width: 26, height: 27)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(deadline.isDone ? "恢复 \(deadline.title)" : "完成 \(deadline.title)")
                    .help(deadline.isDone ? "取消完成" : "标记完成")

                    if let value = deadline.link, let link = PlanDeadline.webLink(value.absoluteString) {
                        Link(destination: link) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .frame(width: 26, height: 27)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("打开链接 \(deadline.title)")
                        .help(link.absoluteString)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 82, alignment: .top)

            Rectangle().fill(palette.line).frame(height: 1)

            Text(deadline.dateLabel)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 22, alignment: .leading)
                .accessibilityLabel("截止时间 \(deadline.dateLabel)")

            Group {
                if deadline.showsCountdown && !deadline.isDone {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let time = DeadlineCountdown(dueAt: deadline.dueAt, now: context.date)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(time.statusLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .fixedSize()
                            Text(time.durationLabel)
                                .font(.system(size: 23, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .foregroundStyle(palette.warning)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .background(
                            palette.warning.opacity(time.isOverdue ? 0.14 : 0.08),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(time.label)
                    }
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(height: 38)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(BoardCard(palette: palette))
    }
}

private struct DeadlineForm: View {
    @State var draft: DeadlineDraft
    let store: PlanStore
    let palette: BoardPalette
    let close: () -> Void
    @FocusState private var titleFocused: Bool

    var body: some View {
        let linkText = draft.linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = PlanDeadline.webLink(linkText)
        let invalidLink = !linkText.isEmpty && link == nil

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
            VStack(alignment: .leading, spacing: 4) {
                Text("链接（选填）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.muted)
                TextField("链接（选填）", text: $draft.linkText, prompt: Text("https://…"))
                    .font(.system(size: 13))
                    .accessibilityLabel("链接（选填）")
                if invalidLink {
                    Text("请输入以 http:// 或 https:// 开头的网址")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.warning)
                }
            }
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
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if store.saveDeadline(
                        draft.title,
                        dueAt: draft.dueAt,
                        showsCountdown: draft.showsCountdown,
                        link: link,
                        editing: draft.deadlineID
                    ) {
                        close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(invalidLink || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    var linkText: String
}
