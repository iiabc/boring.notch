import SwiftUI

enum SystemMonitorIslandKind: String, CaseIterable, Identifiable {
    case memory
    case cpu
    case storage
    case network

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .memory: "Memory"
        case .cpu: "CPU"
        case .storage: "Storage"
        case .network: "Network"
        }
    }

    var icon: String {
        switch self {
        case .memory: "memorychip"
        case .cpu: "cpu"
        case .storage: "internaldrive"
        case .network: "network"
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

struct MetricTrendView: View {
    let samples: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            if points.count > 1 {
                areaPath(points: points, in: geo.size)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.25), accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                linePath(points: points)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .animation(.smooth(duration: 0.6), value: samples)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let peak = max(samples.max() ?? 0, 0.001)
        let stepX = size.width / CGFloat(samples.count - 1)
        return samples.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * stepX,
                y: size.height - CGFloat(value / peak) * (size.height - 4) - 2
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
        }
    }

    private func areaPath(points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            path.addLines(points)
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
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
    var trendSamples: [Double]? = nil
    var trailing: AnyView? = nil

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
            if let trendSamples {
                MetricTrendView(samples: trendSamples, accent: accent)
                    .frame(width: 170, height: 54)
            } else if let trailing {
                trailing
            }
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
            showsBackground: showsBackground,
            trendSamples: monitor.memoryHistory
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
                MetricIslandDetail(title: "Load 1m", value: String(format: "%.2f", monitor.loadAverage1m)),
                MetricIslandDetail(title: "Load 5m", value: String(format: "%.2f", monitor.loadAverage5m))
            ],
            showsBackground: showsBackground,
            trendSamples: monitor.cpuHistory
        )
    }
}

struct NetworkMetricIslandView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    var showsBackground = true

    private var progress: Double {
        guard monitor.networkPeakRate > 0 else { return 0 }
        return min(1, max(0, monitor.networkDownloadRate / monitor.networkPeakRate))
    }

    var body: some View {
        MetricIslandView(
            title: String(localized: "Network speed"),
            systemImage: "network",
            accent: .green,
            progress: progress,
            valueText: MetricIslandView.formatRate(monitor.networkDownloadRate),
            details: [
                MetricIslandDetail(title: "Up", value: MetricIslandView.formatRate(monitor.networkUploadRate)),
                MetricIslandDetail(title: "Peak", value: MetricIslandView.formatRate(monitor.networkPeakRate))
            ],
            showsBackground: showsBackground,
            trendSamples: monitor.networkHistory
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
                MetricIslandDetail(title: "Total", value: Self.formatBytes(volume.totalBytes)),
                MetricIslandDetail(title: "Purgeable", value: Self.formatBytes(volume.purgeableBytes))
            ],
            showsBackground: showsBackground,
            trailing: AnyView(storageTrailing(volume: volume))
        )
    }

    private static func storageTrailing(volume: SystemVolumeStatus) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Self.formatBytes(volume.availableBytes))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("Free")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    static func percentage(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .file)
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var value = max(0, bytesPerSecond)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let number: String
        if value >= 100 || unitIndex == 0 {
            number = "\(Int(value.rounded()))"
        } else {
            number = String(format: "%.1f", value)
        }
        return "\(number)\(units[unitIndex])/s"
    }
}

// MARK: - Per-process detail panel (iStat Menus style)

struct ProcessDetailPanel: View {
    enum Kind {
        case memory
        case cpu
    }

    let kind: Kind
    @ObservedObject private var monitor = SystemMonitorManager.shared

    private var processes: [MonitoredProcess] {
        switch kind {
        case .memory: monitor.topMemoryProcesses
        case .cpu: monitor.topCPUProcesses
        }
    }

    private var title: String {
        switch kind {
        case .memory: String(localized: "Top Memory")
        case .cpu: String(localized: "Top CPU")
        }
    }

    private var subtitle: String {
        switch kind {
        case .memory: String(localized: "Physical memory · Top 8")
        case .cpu: String(localized: "% CPU · Top 8")
        }
    }

    private var accent: Color {
        switch kind {
        case .memory: .purple
        case .cpu: .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.15))
            if processes.isEmpty {
                Text("Collecting data…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        ProcessRow(process: process, kind: kind)
                        if index < processes.count - 1 {
                            Divider().overlay(Color.white.opacity(0.06))
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 384, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: kind == .memory ? "memorychip" : "cpu")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ProcessRow: View {
    let process: MonitoredProcess
    let kind: ProcessDetailPanel.Kind

    var body: some View {
        HStack(spacing: 10) {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            Text(process.name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(valueText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var valueText: String {
        switch kind {
        case .memory: MetricIslandView.formatBytes(process.memoryBytes)
        case .cpu: String(format: "%.1f%%", process.cpuPercent)
        }
    }
}

@MainActor
final class ProcessDetailWindowManager {
    static let shared = ProcessDetailWindowManager()

    private static let panelSize = NSSize(width: 340, height: 384)

    private var window: BoringNotchSkyLightWindow?
    private var activeKind: ProcessDetailPanel.Kind?
    private var mouseDownGlobal: Any?
    private var mouseDownLocal: Any?
    private var scheduledHide: Task<Void, Never>?

    private init() {}

    var isShowing: Bool { window != nil }

    func toggle(kind: ProcessDetailPanel.Kind, for viewModel: BoringViewModel) {
        scheduledHide?.cancel()
        scheduledHide = nil
        if activeKind == kind {
            hide()
        } else {
            show(kind: kind, for: viewModel)
        }
    }

    func show(kind: ProcessDetailPanel.Kind, for viewModel: BoringViewModel) {
        hide()
        activeKind = kind

        guard let screen = viewModel.screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) ?? NSScreen.main else {
            activeKind = nil
            return
        }
        let screenFrame = screen.frame
        let notchBottomY = screenFrame.maxY - windowSize.height
        let frame = NSRect(
            x: screenFrame.midX - Self.panelSize.width / 2,
            y: notchBottomY - IslandWindowManager.islandGap - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )

        let panel = BoringNotchSkyLightWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .mainMenu + 4
        panel.contentView = NSHostingView(
            rootView: ProcessDetailPanel(kind: kind).preferredColorScheme(.dark)
        )
        panel.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(panel)
        window = panel
        installDismissMonitors()
    }

    func hide() {
        scheduledHide?.cancel()
        scheduledHide = nil
        removeDismissMonitors()
        activeKind = nil
        if let window {
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            window.close()
            self.window = nil
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        mouseDownGlobal = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick() }
        }
        mouseDownLocal = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick() }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let mouseDownGlobal { NSEvent.removeMonitor(mouseDownGlobal) }
        if let mouseDownLocal { NSEvent.removeMonitor(mouseDownLocal) }
        mouseDownGlobal = nil
        mouseDownLocal = nil
    }

    private func handleOutsideClick() {
        guard let window, activeKind != nil else { return }
        let location = NSEvent.mouseLocation
        if window.frame.contains(location) {
            scheduledHide?.cancel()
            scheduledHide = nil
            return
        }
        guard scheduledHide == nil else { return }
        scheduledHide = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }
}
