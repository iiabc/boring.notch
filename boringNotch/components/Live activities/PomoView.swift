import Defaults
import SwiftUI

struct PomoLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = PomoManager.shared
    let height: CGFloat

    private var phaseColor: Color {
        color(for: manager.phase)
    }

    private func color(for phase: PomoPhase) -> Color {
        switch phase {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if let notice = manager.completionNotice {
                    dropdownContent(for: notice)
                        .transition(.opacity)
                } else {
                    liveRow(at: context.date)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.25), value: manager.completionNotice != nil)
        }
    }

    private func dropdownContent(for notice: PomoCompletionNotice) -> some View {
        VStack(spacing: 3) {
            Spacer(minLength: 0)
            Image(systemName: notice.phase.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color(for: notice.phase))
            Text(notice.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(notice.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
        .frame(width: vm.closedNotchSize.width + 12, height: height, alignment: .bottom)
    }

    private func liveRow(at date: Date) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: manager.phase.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(phaseColor)
                Text(manager.phase.compactTitle)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 7) {
                Text(manager.formattedRemaining(at: date))
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                if manager.status == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                if manager.phase != .work {
                    Capsule().fill(phaseColor.opacity(0.25))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: height, alignment: .center)
    }
}

struct PomoTabView: View {
    @ObservedObject private var manager = PomoManager.shared
    @Default(.pomoDailyGoal) private var dailyGoal
    @State private var taskTitle = ""

    private var phaseColor: Color {
        color(for: manager.phase)
    }

    private func color(for phase: PomoPhase) -> Color {
        switch phase {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }

    private var goalProgress: Double {
        min(Double(manager.todayFocusSessions) / Double(max(dailyGoal, 1)), 1)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 22) {
                timerRing(at: context.date)
                controlColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { taskTitle = manager.taskTitle }
        .onChange(of: manager.taskTitle) { _, newValue in
            if taskTitle != newValue { taskTitle = newValue }
        }
        .navigationTitle("Pomodoro")
    }

    private func timerRing(at date: Date) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 7)
            Circle()
                .trim(from: 0, to: manager.progress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: manager.progress)

            VStack(spacing: 2) {
                Text(manager.formattedRemaining(at: date))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(manager.completionNotice?.message ?? manager.statusTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 116, height: 116)
        .contentShape(Circle())
        .onTapGesture { manager.toggle() }
        .help(
            manager.status == .running
                ? String(localized: "Pause")
                : String(localized: "Start")
        )
    }

    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(manager.phase.compactTitle, systemImage: manager.phase.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phaseColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(phaseColor.opacity(0.15), in: Capsule())

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Text("\(manager.todayFocusSessions)/\(dailyGoal)")
                        .monospacedDigit()
                    ProgressView(value: goalProgress)
                        .tint(.orange)
                        .frame(width: 44)
                    Text("\(manager.todayFocusMinutes) \(String(localized: "min"))")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            TextField(String(localized: "What are you working on?"), text: $taskTitle)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(height: 22)
                .onSubmit { manager.updateTaskTitle(taskTitle) }

            HStack(spacing: 8) {
                Button {
                    manager.toggle()
                } label: {
                    Label(
                        manager.status == .running
                            ? String(localized: "Pause")
                            : String(localized: "Start"),
                        systemImage: manager.status == .running ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(phaseColor)
                .controlSize(.small)

                Button {
                    manager.addMinute()
                } label: {
                    Text("+1m")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "Add one minute"))

                Menu {
                    Button(String(localized: "Skip to next phase")) {
                        manager.skip()
                    }
                    Button(String(localized: "Reset phase")) {
                        manager.resetCurrentPhase()
                    }
                    Button(String(localized: "Stop"), role: .destructive) {
                        manager.stop()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 20)
                }
                .menuStyle(.borderlessButton)
                .help(String(localized: "More timer actions"))
            }
        }
        .frame(width: 252)
    }
}
