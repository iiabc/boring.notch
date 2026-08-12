import Defaults
import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject private var monitor = SystemMonitorManager.shared
    @EnvironmentObject private var vm: BoringViewModel

    @Default(.systemMonitorMemoryVisible) private var memoryVisible
    @Default(.systemMonitorCpuVisible) private var cpuVisible
    @Default(.systemMonitorStorageVisible) private var storageVisible
    @Default(.systemMonitorIslandOrder) private var islandOrder

    private let islandHeight: CGFloat = 108

    private var visibleKinds: [SystemMonitorIslandKind] {
        SystemMonitorIslandKind.ordered(order: islandOrder).filter { kind in
            switch kind {
            case .memory: memoryVisible
            case .cpu: cpuVisible
            case .storage: storageVisible
            }
        }
    }

    private var configSignature: String {
        "\(memoryVisible)|\(cpuVisible)|\(storageVisible)|\(islandOrder.joined(separator: ","))"
    }

    var body: some View {
        Group {
            if let first = visibleKinds.first {
                islandContent(for: first, showsBackground: false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            } else {
                Text("All system monitors are hidden")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            monitor.startMonitoring()
            presentIslands()
        }
        .onDisappear {
            monitor.stopMonitoring()
            IslandWindowManager.shared.dismiss(for: vm)
        }
        .onChange(of: vm.notchState) {
            if vm.notchState == .closed {
                IslandWindowManager.shared.dismiss(for: vm)
            } else {
                presentIslands()
            }
        }
        .onChange(of: configSignature) {
            rePresentIslands()
        }
        .onChange(of: monitor.externalVolumes.count) { _, _ in
            rePresentIslands()
        }
    }

    @ViewBuilder
    private func islandContent(for kind: SystemMonitorIslandKind, showsBackground: Bool) -> some View {
        switch kind {
        case .memory:
            MemoryMetricIslandView(showsBackground: showsBackground)
        case .cpu:
            CPUMetricIslandView(showsBackground: showsBackground)
        case .storage:
            StorageIslandStackView(monitor: monitor, showsBackground: showsBackground)
        }
    }

    private func presentIslands() {
        let floating = Array(visibleKinds.dropFirst())
        guard !floating.isEmpty else {
            IslandWindowManager.shared.dismiss(for: vm)
            return
        }
        let storagePeek: CGFloat = monitor.externalVolumes.isEmpty ? 0 : 22
        IslandWindowManager.shared.present(
            islands: floating.map { kind in
                FloatingIsland(
                    id: kind.rawValue,
                    height: islandHeight + (kind == .storage ? storagePeek : 0)
                ) {
                    islandContent(for: kind, showsBackground: true)
                }
            },
            for: vm
        )
    }

    private func rePresentIslands() {
        IslandWindowManager.shared.dismiss(for: vm, animated: false)
        presentIslands()
    }
}
