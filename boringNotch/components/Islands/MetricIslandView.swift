import AppKit
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

@MainActor
final class ProcessDetailPopoverController: NSObject, ObservableObject {
    @Published private(set) var dismissRequested = false

    var windowFrame: NSRect = .zero

    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?

    func startMonitoring() {
        stopMonitoring()
        dismissRequested = false

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMouseDown(at: NSEvent.mouseLocation)
            }
        }
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleMouseDown(at: location)
            }
            return event
        }
    }

    func stopMonitoring() {
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
        }
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
        }
        globalMouseDownMonitor = nil
        localMouseDownMonitor = nil
        windowFrame = .zero
    }

    func consumeDismissRequest() {
        dismissRequested = false
    }

    private func handleMouseDown(at location: NSPoint) {
        guard !windowFrame.isEmpty, !windowFrame.contains(location) else { return }
        dismissRequested = true
    }

    deinit {
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
        }
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
        }
    }
}

private struct ProcessDetailPopoverWindowTracker: NSViewRepresentable {
    let onFrameChange: (NSRect) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onFrameChange: onFrameChange)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.updateWindowFrame()
    }

    final class TrackingView: NSView {
        var onFrameChange: (NSRect) -> Void

        init(onFrameChange: @escaping (NSRect) -> Void) {
            self.onFrameChange = onFrameChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindowFrame()
        }

        override func layout() {
            super.layout()
            updateWindowFrame()
        }

        func updateWindowFrame() {
            guard let window else { return }
            onFrameChange(window.frame)
        }
    }
}

struct ProcessDetailIsland<Content: View>: View {
    let kind: ProcessDetailPanel.Kind
    let content: Content
    @ObservedObject private var viewModel: BoringViewModel
    @State private var isPresented = false
    @StateObject private var popoverController = ProcessDetailPopoverController()

    init(
        kind: ProcessDetailPanel.Kind,
        viewModel: BoringViewModel,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.content = content()
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                isPresented.toggle()
            }
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ProcessDetailPanel(kind: kind, popoverController: popoverController)
                    .preferredColorScheme(.dark)
            }
            .onChange(of: isPresented) { _, presented in
                viewModel.isProcessDetailPopoverActive = presented
                if presented {
                    popoverController.startMonitoring()
                } else {
                    popoverController.stopMonitoring()
                }
            }
            .onChange(of: popoverController.dismissRequested) { _, requested in
                guard requested else { return }
                popoverController.consumeDismissRequest()
                isPresented = false
            }
            .onDisappear {
                popoverController.stopMonitoring()
                viewModel.isProcessDetailPopoverActive = false
            }
    }
}

struct ProcessDetailPanel: View {
    enum Kind {
        case memory
        case cpu
    }

    let kind: Kind
    var popoverController: ProcessDetailPopoverController?
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
        .padding(.vertical, 8)
        .background {
            if let popoverController {
                ProcessDetailPopoverWindowTracker { frame in
                    popoverController.windowFrame = frame
                }
                .allowsHitTesting(false)
            }
        }
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
