import AppKit
import SwiftUI

struct DesktopPlanCard: View {
    @ObservedObject var store: PlanStore
    let open: () -> Void

    private let calendar = PlanCalendar()
    private let quiet = Color.white.opacity(0.78)
    private let ice = Color(red: 0.76, green: 0.89, blue: 1)

    var body: some View {
        TimelineView(.everyMinute) { context in
            card(at: context.date)
        }
        .padding(17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [
                Color(red: 0.075, green: 0.23, blue: 0.48),
                Color(red: 0.17, green: 0.43, blue: 0.68)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.23), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func card(at date: Date) -> some View {
        let day = calendar.dayKey(date)
        let week = calendar.dayKey(calendar.weekStart(for: date))
        let goals = store.plan[.goal(week)]
        let today = store.plan[.day(day)]
        let note = store.plan[noteFor: day]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("周计划", systemImage: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .overlay {
                        CardDragHandle()
                            .accessibilityHidden(true)
                    }
                Spacer()
                Text("\(calendar.shortDate(date)) · \(calendar.weekday(date))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(quiet)
                    .monospacedDigit()
                Button(action: open) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 23, height: 23)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开周计划")
                .help("打开周计划")
            }

            deadline
            taskSection("本周目标", items: goals, limit: 1)
            taskSection("今日待办", items: today, limit: 3)
            if !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(.system(size: 11))
                    .foregroundStyle(quiet)
                    .lineLimit(1)
            }
        }
    }

    private var deadline: some View {
        HStack(spacing: 8) {
            Text("DDL")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ice)
            if let next = store.plan.firstOpenDeadline {
                Text(next.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let time = DeadlineCountdown(dueAt: next.dueAt, now: context.date)
                    Text(time.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(time.isOverdue ? Color(red: 1, green: 0.80, blue: 0.67) : ice)
                        .monospacedDigit()
                        .fixedSize()
                }
            } else {
                Text("暂无未完成的截止事项")
                    .font(.system(size: 11))
                    .foregroundStyle(quiet)
                Spacer()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func taskSection(_ title: String, items: [PlanTask], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ice)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.filter(\.isDone).count)/\(items.count)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(quiet)
                }
            }
            if items.isEmpty {
                Text("暂无安排")
                    .font(.system(size: 11))
                    .foregroundStyle(quiet)
            } else {
                ForEach(items.prefix(limit)) { task in
                    Label {
                        Text(task.title)
                            .strikethrough(task.isDone)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(task.isDone ? quiet : .white)
                }
            }
        }
    }
}

private struct CardDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
