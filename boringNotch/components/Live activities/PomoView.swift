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
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if let notice = manager.completionNotice {
                        Image(systemName: notice.phase.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(for: notice.phase))
                        Text(notice.title)
                            .font(.caption)
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: manager.phase.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(phaseColor)
                        Text(manager.phase.compactTitle)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                Rectangle()
                    .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

                HStack(spacing: 7) {
                    Group {
                        if let notice = manager.completionNotice {
                            Text(notice.message)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text(manager.formattedRemaining(at: context.date))
                                .font(.system(.subheadline, design: .monospaced))
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    if manager.completionNotice == nil && manager.status == .paused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            }
            .frame(height: height, alignment: .center)
        }
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
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Label(manager.phase.compactTitle, systemImage: manager.phase.symbolName)
                        .foregroundStyle(phaseColor)
                    Spacer()
                    if let notice = manager.completionNotice {
                        Text(notice.message)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(manager.statusTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)

                HStack(alignment: .center, spacing: 12) {
                    Text(manager.formattedRemaining(at: context.date))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(manager.todayFocusSessions)/\(dailyGoal) · \(manager.todayFocusMinutes) \(String(localized: "min"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        ProgressView(value: goalProgress)
                            .tint(.orange)
                            .frame(width: 96)
                    }
                }

                ProgressView(value: manager.progress)
                    .tint(phaseColor)

                TextField(String(localized: "What are you working on?"), text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(height: 22)
                    .onSubmit { manager.updateTaskTitle(taskTitle) }

                HStack(spacing: 6) {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { taskTitle = manager.taskTitle }
        .onChange(of: manager.taskTitle) { _, newValue in
            if taskTitle != newValue { taskTitle = newValue }
        }
        .navigationTitle("Pomodoro")
    }
}
