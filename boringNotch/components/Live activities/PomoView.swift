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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 14) {
                HStack {
                    Label(manager.phase.title, systemImage: manager.phase.symbolName)
                        .foregroundStyle(phaseColor)
                    Spacer()
                    Text(manager.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                }

                Text(manager.formattedRemaining(at: context.date))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                ProgressView(value: manager.progress)
                    .tint(phaseColor)

                TextField("What are you working on?", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { manager.updateTaskTitle(taskTitle) }

                HStack(spacing: 8) {
                    Button {
                        manager.toggle()
                    } label: {
                        Label(manager.status == .running ? "Pause" : "Start", systemImage: manager.status == .running ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        manager.skip()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .help("Skip to next phase")

                    Button {
                        manager.resetCurrentPhase()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Reset phase")

                    Button {
                        manager.addMinute()
                    } label: {
                        Text("+1m")
                    }
                    .help("Add one minute")
                }

                HStack {
                    Text("Completed focus sessions")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(manager.completedWorkSessions)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.caption)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { taskTitle = manager.taskTitle }
        .onChange(of: manager.taskTitle) { _, newValue in
            if taskTitle != newValue { taskTitle = newValue }
        }
        .navigationTitle("Pomodoro")
    }
}
