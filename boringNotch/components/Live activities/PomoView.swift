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
    @EnvironmentObject var vm: BoringViewModel
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

    private var tabsHeight: CGFloat {
        max(24, vm.effectiveClosedNotchHeight)
    }

    private var contentHeight: CGFloat {
        max(0, vm.notchSize.height - tabsHeight)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: tabsHeight)
                    .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        PomoMetric(
                            title: String(localized: "Today"),
                            value: "\(manager.todayFocusSessions)/\(dailyGoal)"
                        )
                        PomoMetric(
                            title: String(localized: "Focus time"),
                            value: "\(manager.todayFocusMinutes) \(String(localized: "min"))"
                        )
                        PomoMetric(
                            title: String(localized: "This week"),
                            value: "\(manager.weekFocusMinutes) \(String(localized: "min"))"
                        )
                    }

                    if let notice = manager.completionNotice {
                        HStack {
                            Label(notice.title, systemImage: notice.phase.symbolName)
                                .foregroundStyle(color(for: notice.phase))
                            Spacer()
                            Text(notice.message)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(spacing: 9) {
                        HStack {
                            Label(manager.phase.title, systemImage: manager.phase.symbolName)
                                .foregroundStyle(phaseColor)
                            Spacer()
                            Text(manager.statusTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(manager.formattedRemaining(at: context.date))
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        ProgressView(value: manager.progress)
                            .tint(phaseColor)

                        TextField(String(localized: "What are you working on?"), text: $taskTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { manager.updateTaskTitle(taskTitle) }

                        HStack(spacing: 7) {
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

                            Button {
                                manager.addMinute()
                            } label: {
                                Text("+1m")
                            }
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
                                    .frame(width: 28, height: 24)
                            }
                            .help(String(localized: "More timer actions"))
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack {
                        Text(String(localized: "Daily goal"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(manager.todayFocusSessions)/\(dailyGoal)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.caption)

                    ProgressView(value: goalProgress)
                        .tint(.orange)

                    if !manager.recentHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Recent sessions"))
                                .font(.headline)

                            ForEach(manager.recentHistory) { record in
                                HStack(spacing: 8) {
                                    Image(systemName: record.phase.symbolName)
                                        .foregroundStyle(color(for: record.phase))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.taskTitle.isEmpty ? record.phase.title : record.taskTitle)
                                            .lineLimit(1)
                                        Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(PomoManager.formatTime(record.duration))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
                .frame(width: vm.notchSize.width, height: contentHeight, alignment: .top)
            }
            .frame(width: vm.notchSize.width, height: vm.notchSize.height, alignment: .top)
        }
        .onAppear { taskTitle = manager.taskTitle }
        .onChange(of: manager.taskTitle) { _, newValue in
            if taskTitle != newValue { taskTitle = newValue }
        }
        .navigationTitle("Pomodoro")
    }
}

private struct PomoMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
