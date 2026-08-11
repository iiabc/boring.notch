import Defaults
import SwiftUI

struct PomodoroSettings: View {
    @ObservedObject private var manager = PomoManager.shared
    @Default(.pomoWorkDuration) private var workDuration
    @Default(.pomoShortBreakDuration) private var shortBreakDuration
    @Default(.pomoLongBreakDuration) private var longBreakDuration
    @Default(.pomoLongBreakInterval) private var longBreakInterval
    @Default(.pomoAutoStartNext) private var autoStartNext
    @Default(.pomoNotchNotifications) private var notchNotifications
    @Default(.pomoSound) private var sound

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .pomoEnabled) {
                    Text("Enable Pomodoro")
                }
                Defaults.Toggle(key: .pomoShowInNotch) {
                    Text("Show active timer in the closed notch")
                }
            } header: {
                Text("Pomodoro")
            }

            Section {
                durationStepper("Focus", value: $workDuration, range: 5 * 60...120 * 60)
                durationStepper("Short break", value: $shortBreakDuration, range: 1 * 60...30 * 60)
                durationStepper("Long break", value: $longBreakDuration, range: 5 * 60...60 * 60)
                Stepper(value: $longBreakInterval, in: 2...12) {
                    HStack {
                        Text("Long break after")
                        Spacer()
                        Text("\(longBreakInterval) focus sessions")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Durations")
            }

            Section {
                Toggle("Automatically start the next phase", isOn: $autoStartNext)
                Toggle("Show completion in the notch", isOn: $notchNotifications)
                Toggle("Play a sound on completion", isOn: $sound)
            } header: {
                Text("Behavior")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(manager.phase.title)
                            .font(.headline)
                        Text(manager.statusTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(manager.status == .running ? "Pause" : "Start") {
                        manager.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Stop") {
                        manager.stop()
                    }
                }

                if !manager.taskTitle.isEmpty {
                    Text(manager.taskTitle)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Current session")
            }
        }
        .onChange(of: workDuration) { _, _ in manager.refreshConfiguration() }
        .onChange(of: shortBreakDuration) { _, _ in manager.refreshConfiguration() }
        .onChange(of: longBreakDuration) { _, _ in manager.refreshConfiguration() }
        .navigationTitle("Pomodoro")
        .accentColor(.effectiveAccent)
    }

    private func durationStepper(
        _ title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>
    ) -> some View {
        Stepper(value: value, in: range, step: 60) {
            HStack {
                Text(title)
                Spacer()
                Text(PomoManager.formatTime(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
