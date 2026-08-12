import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject private var monitor = SystemMonitorManager.shared
    @EnvironmentObject private var vm: BoringViewModel

    private let islandHeight: CGFloat = 108

    var body: some View {
        MemoryMetricIslandView()
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                monitor.startMonitoring()
                presentIslands()
            }
            .onDisappear {
                monitor.stopMonitoring()
                IslandWindowManager.shared.dismiss(for: vm)
            }
            .onChange(of: monitor.externalVolumes.count) { _, _ in
                IslandWindowManager.shared.dismiss(for: vm, animated: false)
                presentIslands()
            }
    }

    private func presentIslands() {
        let storageStackPeek: CGFloat = monitor.externalVolumes.isEmpty ? 0 : 22
        IslandWindowManager.shared.present(
            islands: [
                FloatingIsland(id: "cpu", height: islandHeight) {
                    CPUMetricIslandView()
                },
                FloatingIsland(id: "storage", height: islandHeight + storageStackPeek) {
                    StorageIslandStackView(monitor: SystemMonitorManager.shared)
                }
            ],
            for: vm
        )
    }
}
