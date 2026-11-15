import SwiftUI

struct IdeaBoard: View {
    @ObservedObject var store: PlanStore
    var isActive = true
    @Environment(\.colorScheme) private var scheme
    @FocusState private var captureFocused: Bool
    @State private var capture = ""
    @State private var filter: IdeaStatus?
    @State private var editing: PlanIdea?

    private var palette: BoardPalette { BoardPalette(dark: scheme == .dark) }

    private var visibleIdeas: [PlanIdea] {
        store.plan.ideaItems.reversed().filter { filter == nil || $0.status == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let editing {
                IdeaEditor(store: store, original: editing, palette: palette) { self.editing = nil }
                    .id(editing.id)
            } else {
                captureBox
                if !store.plan.ideaItems.isEmpty {
                    Picker("按验证状态筛选", selection: $filter) {
                        Text("全部").tag(nil as IdeaStatus?)
                        ForEach(IdeaStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(Optional(status))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                ideaList
            }

            if let message = store.errorMessage {
                HStack {
                    Label(message, systemImage: "exclamationmark.circle")
                    if !store.isReady {
                        Spacer()
                        Button("重试", action: store.load)
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(palette.warning)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
        .onChange(of: isActive) { _, active in
            captureFocused = active && editing == nil
        }
    }

    private var captureBox: some View {
        HStack(spacing: 10) {
            TextField("记下一条 Idea", text: $capture, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(palette.ink)
                .lineLimit(1...4)
                .padding(.vertical, 4)
                .focused($captureFocused)
                .onAppear { captureFocused = isActive }
                .accessibilityLabel("新的 Idea")

            Button {
                guard store.addIdea(capture) else { return }
                capture = ""
                if filter != .pending { filter = nil }
                captureFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 28, height: 28)
                    .background(palette.blueWash, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!store.isReady || capture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("添加 Idea")
            .help("添加 Idea（⌘↩）")
        }
        .padding(9)
        .modifier(BoardCard(palette: palette))
    }

    private var ideaList: some View {
        let ideas = visibleIdeas
        return ScrollView {
            if ideas.isEmpty {
                Text(filter == nil ? "还没有 Idea" : "这个状态下暂无 Idea")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 25)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(ideas) { idea in
                        if idea.id != ideas.first?.id { Divider() }
                        ideaRow(idea)
                    }
                }
                .modifier(BoardCard(palette: palette))
            }
        }
    }

    private func ideaRow(_ idea: PlanIdea) -> some View {
        let statusColor = switch idea.status {
        case .pending: palette.muted
        case .testing: palette.accent
        case .verified: palette.success
        }
        return Button {
            editing = idea
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(idea.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(idea.createdAt.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(idea.status.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("编辑 Idea 和验证记录")
    }
}

private struct IdeaEditor: View {
    @ObservedObject var store: PlanStore
    let original: PlanIdea
    let palette: BoardPalette
    let close: () -> Void

    @State private var draft: PlanIdea
    @State private var confirmDelete = false

    init(store: PlanStore, original: PlanIdea, palette: BoardPalette, close: @escaping () -> Void) {
        self.store = store
        self.original = original
        self.palette = palette
        self.close = close
        _draft = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("编辑 Idea")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("删除", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.warning)
                Button("取消", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if store.saveIdea(draft, replacing: original) { close() }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("保存（⌘↩）")
            }
            .controlSize(.small)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    field("想法", placeholder: "写下想法", text: $draft.title, lines: 1...4)
                    Picker("验证状态", selection: $draft.status) {
                        ForEach(IdeaStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    field("验证方法", placeholder: "要做的实验、对照或下一步", text: $draft.verificationPlan, lines: 2...6)
                    field("验证结果", placeholder: "结论、指标或证据链接", text: $draft.verificationResult, lines: 2...6)
                }
            }
        }
        .confirmationDialog("删除这条 Idea？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除 Idea", role: .destructive) {
                if store.removeIdea(original.id) { close() }
            }
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.muted)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(palette.ink)
                .lineLimit(lines)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .modifier(BoardCard(palette: palette))
    }
}
