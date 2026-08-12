import SwiftUI

enum SystemMonitorIslandKind: String, CaseIterable, Identifiable {
    case memory
    case cpu
    case storage

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .memory: "Memory"
        case .cpu: "CPU"
        case .storage: "Storage"
        }
    }

    var icon: String {
        switch self {
        case .memory: "memorychip"
        case .cpu: "cpu"
        case .storage: "internaldrive"
        }
    }

    static func ordered(order: [String]) -> [SystemMonitorIslandKind] {
        var result = order.compactMap { SystemMonitorIslandKind(rawValue: $0) }
        for kind in allCases where !result.contains(kind) {
            result.append(kind)
        }
        return result
    }
}

struct MetricIslandDetail: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let value: String
}

struct MetricIslandView: View {
    let title: String
    let systemImage: String
    let accent: Color
    let progress: Double
    let valueText: String
    let details: [MetricIslandDetail]
    var ringSize: CGFloat = 76
    var showsBackground: Bool = true

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 18) {
                    ForEach(details) { detail in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(detail.value)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: cornerRadiusInsets.opened.bottom, style: .continuous)
                    .fill(.black)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.6), accent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * clampedProgress)
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.5), radius: 4)
                .animation(.smooth(duration: 0.6), value: clampedProgress)
            Text(valueText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: valueText)
        }
        .frame(width: ringSize, height: ringSize)
    }
}

struct MemoryMetricIslandView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    var showsBackground = true

    private var usage: Double {
        guard monitor.totalMemoryBytes > 0 else { return 0 }
        return min(1, max(0, Double(monitor.usedMemoryBytes) / Double(monitor.totalMemoryBytes)))
    }

    var body: some View {
        MetricIslandView(
            title: String(localized: "Memory usage"),
            systemImage: "memorychip",
            accent: .purple,
            progress: usage,
            valueText: MetricIslandView.percentage(usage),
            details: [
                MetricIslandDetail(title: "Used", value: MetricIslandView.formatBytes(monitor.usedMemoryBytes)),
                MetricIslandDetail(title: "Total", value: MetricIslandView.formatBytes(monitor.totalMemoryBytes))
            ],
            showsBackground: showsBackground
        )
    }
}

struct CPUMetricIslandView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    var showsBackground = true

    var body: some View {
        MetricIslandView(
            title: String(localized: "CPU usage"),
            systemImage: "cpu",
            accent: .blue,
            progress: monitor.cpuUsage,
            valueText: MetricIslandView.percentage(monitor.cpuUsage),
            details: [
                MetricIslandDetail(title: "Cores", value: "\(monitor.cpuCoreCount)"),
                MetricIslandDetail(title: "Updated", value: "1s")
            ],
            showsBackground: showsBackground
        )
    }
}

extension MetricIslandView {
    static func storage(volume: SystemVolumeStatus, showsBackground: Bool = true) -> MetricIslandView {
        MetricIslandView(
            title: volume.name,
            systemImage: volume.mountPoint == "/" ? "internaldrive" : "externaldrive",
            accent: .orange,
            progress: volume.usage,
            valueText: Self.percentage(volume.usage),
            details: [
                MetricIslandDetail(title: "Used", value: Self.formatBytes(volume.usedBytes)),
                MetricIslandDetail(title: "Free", value: Self.formatBytes(volume.availableBytes))
            ],
            showsBackground: showsBackground
        )
    }

    static func percentage(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .file)
    }
}
