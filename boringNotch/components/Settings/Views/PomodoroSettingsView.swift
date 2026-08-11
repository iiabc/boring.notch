import Defaults
import SwiftUI

struct PomodoroSettings: View {
    @ObservedObject private var manager = PomoManager.shared
    @Default(.pomoWorkDuration) private var workDuration
    @Default(.pomoShortBreakDuration) private var shortBreakDuration
    @Default(.pomoLongBreakDuration) private var longBreakDuration
    @Default(.pomoLongBreakInterval) private var longBreakInterval
    @Default(.pomoDailyGoal) private var dailyGoal
    @Default(.pomoAutoStartNext) private var autoStartNext
    @Default(.pomoNotchNotifications) private var notchNotifications
    @Default(.pomoSound) private var sound
    @State private var showingClearHistoryConfirmation = false

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
                Picker("Preset", selection: presetBinding) {
                    ForEach(PomoPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                durationStepper(String(localized: "Focus"), value: $workDuration, range: 5 * 60...120 * 60)
                durationStepper(String(localized: "Short break"), value: $shortBreakDuration, range: 1 * 60...30 * 60)
                durationStepper(String(localized: "Long break"), value: $longBreakDuration, range: 5 * 60...60 * 60)
                Stepper(value: $longBreakInterval, in: 2...12) {
                    HStack {
                        Text("Long break after")
                        Spacer()
                        Text("\(longBreakInterval) \(String(localized: "focus sessions"))")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $dailyGoal, in: 1...16) {
                    HStack {
                        Text("Daily focus goal")
                        Spacer()
                        Text("\(dailyGoal) \(String(localized: "sessions"))")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Plan")
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

            Section {
                HStack(spacing: 8) {
                    Button("Import") {
                        manager.importHistory()
                    }
                    .frame(maxWidth: .infinity)

                    Button("Export") {
                        manager.exportHistory()
                    }
                    .frame(maxWidth: .infinity)
                }

                Button("Clear history", role: .destructive) {
                    showingClearHistoryConfirmation = true
                }

                if let message = manager.dataStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            }
        }
        .onChange(of: workDuration) { _, _ in manager.refreshConfiguration() }
        .onChange(of: shortBreakDuration) { _, _ in manager.refreshConfiguration() }
        .onChange(of: longBreakDuration) { _, _ in manager.refreshConfiguration() }
        .navigationTitle("Pomodoro")
        .accentColor(.effectiveAccent)
        .alert("Clear Pomodoro history?", isPresented: $showingClearHistoryConfirmation) {
            Button("Clear", role: .destructive) {
                manager.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This only removes completed session records. The current timer will not change.")
        }
    }

    private var presetBinding: Binding<PomoPreset> {
        Binding(
            get: {
                PomoPreset.matching(
                    work: workDuration,
                    shortBreak: shortBreakDuration,
                    longBreak: longBreakDuration,
                    interval: longBreakInterval
                )
            },
            set: { manager.applyPreset($0) }
        )
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
