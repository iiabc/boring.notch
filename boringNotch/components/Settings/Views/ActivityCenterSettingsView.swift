import Defaults
import SwiftUI

struct ActivityCenterSettings: View {
    @Default(.notchActivityQuietMode) private var quietMode
    @Default(.notchActivitySuppressDuringFullscreen) private var suppressDuringFullscreen
    @Default(.notchActivityQueueEnabled) private var queueEnabled
    @Default(.notchActivityQuietModeMinimumPriority) private var quietModeMinimumPriority
    @Default(.notchActivityAgentPriority) private var agentPriority
    @Default(.notchActivityBatteryPriority) private var batteryPriority
    @Default(.notchActivityPomodoroPriority) private var pomodoroPriority
    @Default(.notchActivityDownloadPriority) private var downloadPriority
    @Default(.notchActivityOSDPriority) private var osdPriority
    @Default(.notchActivityMusicPriority) private var musicPriority

    var body: some View {
        Form {
            Section {
                Toggle("Quiet mode", isOn: $quietMode)
                Toggle("Suppress activities in full-screen spaces", isOn: $suppressDuringFullscreen)
                Toggle("Queue lower-priority activities", isOn: $queueEnabled)
            } header: {
                Text("Behavior")
            } footer: {
                Text("Quiet mode stays available from the menu bar. Full-screen suppression uses the app's existing full-screen space detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Show activities at or above", selection: $quietModeMinimumPriority) {
                    ForEach(NotchActivityPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Quiet mode")
            } footer: {
                Text("Activities below this priority remain queued while Quiet mode is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                priorityPicker("Agent status", selection: $agentPriority)
                priorityPicker("Battery changes", selection: $batteryPriority)
                priorityPicker("Pomodoro completion", selection: $pomodoroPriority)
                priorityPicker("Downloads", selection: $downloadPriority)
                priorityPicker("OSD", selection: $osdPriority)
                priorityPicker("Music", selection: $musicPriority)
            } header: {
                Text("Priority")
            } footer: {
                Text("When priorities match, the most recently triggered activity is shown first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Activity Center")
    }

    private func priorityPicker(
        _ title: LocalizedStringKey,
        selection: Binding<NotchActivityPriority>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(NotchActivityPriority.allCases) { priority in
                Text(priority.title).tag(priority)
            }
        }
        .pickerStyle(.menu)
    }
}
