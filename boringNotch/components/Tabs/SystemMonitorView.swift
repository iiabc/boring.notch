import SwiftUI

private enum SystemMonitorSection: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case storage
    case external

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .storage: "Storage"
        case .external: "External"
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .storage: "internaldrive"
        case .external: "externaldrive"
        }
    }
}

struct SystemMonitorView: View {
    @ObservedObject private var monitor = SystemMonitorManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @AppStorage("lastSystemMonitorSection") private var selectedSectionRawValue = SystemMonitorSection.cpu.rawValue

    private var selectedSection: SystemMonitorSection {
        SystemMonitorSection(rawValue: selectedSectionRawValue) ?? .cpu
    }

    var body: some View {
        VStack(spacing: 12) {
            sectionPicker
            sectionContent
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !coordinator.openLastTabByDefault {
                selectedSectionRawValue = SystemMonitorSection.cpu.rawValue
            }
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(SystemMonitorSection.allCases) { section in
                Button {
                    withAnimation(.smooth) {
                        selectedSectionRawValue = section.rawValue
                    }
                } label: {
                    Label(section.title, systemImage: section.icon)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSection == section ? .white : .secondary)
                .background {
                    Capsule()
                        .fill(selectedSection == section ? Color(nsColor: .secondarySystemFill) : .clear)
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.45)))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .cpu:
            cpuContent
        case .memory:
            memoryContent
        case .storage:
            storageContent
        case .external:
            externalContent
        }
    }

    private var cpuContent: some View {
        metricContent(
            title: Text("CPU usage"),
            value: percentage(monitor.cpuUsage),
            progress: monitor.cpuUsage,
            systemImage: "cpu"
        ) {
            detailItem(title: "Cores", value: "\(monitor.cpuCoreCount)")
            detailItem(title: "Updated", value: "1s")
        }
    }

    private var memoryContent: some View {
        metricContent(
            title: Text("Memory usage"),
            value: percentage(memoryUsage),
            progress: memoryUsage,
            systemImage: "memorychip"
        ) {
            detailItem(title: "Used", value: formatBytes(monitor.usedMemoryBytes))
            detailItem(title: "Total", value: formatBytes(monitor.totalMemoryBytes))
        }
    }

    private var storageContent: some View {
        metricContent(
            title: Text(monitor.internalStorage.name),
            value: percentage(monitor.internalStorage.usage),
            progress: monitor.internalStorage.usage,
            systemImage: "internaldrive"
        ) {
            detailItem(title: "Used", value: formatBytes(monitor.internalStorage.usedBytes))
            detailItem(title: "Free", value: formatBytes(monitor.internalStorage.availableBytes))
        }
    }

    private var externalContent: some View {
        Group {
            if monitor.externalVolumes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("No external drives connected")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(monitor.externalVolumes) { volume in
                            volumeRow(volume)
                        }
                    }
                }
                .frame(maxHeight: 108)
            }
        }
    }

    private func metricContent<Details: View>(
        title: Text,
        value: String,
        progress: Double,
        systemImage: String,
        @ViewBuilder details: () -> Details
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    title
                } icon: {
                    Image(systemName: systemImage)
                }
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            ProgressView(value: progress)
                .tint(.effectiveAccent)
            HStack {
                details()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func volumeRow(_ volume: SystemVolumeStatus) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(volume.name, systemImage: "externaldrive")
                    .font(.system(.subheadline, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text(percentage(volume.usage))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: volume.usage)
                .tint(.effectiveAccent)
            HStack {
                detailItem(title: "Used", value: formatBytes(volume.usedBytes))
                detailItem(title: "Free", value: formatBytes(volume.availableBytes))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func detailItem(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoryUsage: Double {
        guard monitor.totalMemoryBytes > 0 else { return 0 }
        return min(1, max(0, Double(monitor.usedMemoryBytes) / Double(monitor.totalMemoryBytes)))
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .file)
    }
}
