import Defaults
import SwiftUI

struct SystemMonitorSettings: View {
    @Default(.systemMonitorIslandOrder) var systemMonitorIslandOrder

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .systemMonitorEnabled) {
                    Text("Show system tab")
                }
            } header: {
                Text("General")
            } footer: {
                Text("When disabled, the system tab is hidden from the notch.")
            }

            Section {
                Defaults.Toggle(key: .systemMonitorMemoryVisible) {
                    Label(SystemMonitorIslandKind.memory.title, systemImage: SystemMonitorIslandKind.memory.icon)
                }
                Defaults.Toggle(key: .systemMonitorCpuVisible) {
                    Label(SystemMonitorIslandKind.cpu.title, systemImage: SystemMonitorIslandKind.cpu.icon)
                }
                Defaults.Toggle(key: .systemMonitorStorageVisible) {
                    Label(SystemMonitorIslandKind.storage.title, systemImage: SystemMonitorIslandKind.storage.icon)
                }
            } header: {
                Text("System monitor islands")
            }

            Section {
                ForEach(SystemMonitorIslandKind.ordered(order: systemMonitorIslandOrder)) { kind in
                    HStack {
                        Label(kind.title, systemImage: kind.icon)
                        Spacer()
                        Button {
                            moveIsland(kind, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(islandIndex(kind) == 0)
                        Button {
                            moveIsland(kind, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(islandIndex(kind) == SystemMonitorIslandKind.allCases.count - 1)
                    }
                }
            } header: {
                Text("Island order")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Monitor")
    }

    private func islandIndex(_ kind: SystemMonitorIslandKind) -> Int {
        SystemMonitorIslandKind.ordered(order: systemMonitorIslandOrder).firstIndex(of: kind) ?? 0
    }

    private func moveIsland(_ kind: SystemMonitorIslandKind, offset: Int) {
        var order = SystemMonitorIslandKind.ordered(order: systemMonitorIslandOrder)
        guard let from = order.firstIndex(of: kind) else { return }
        let to = from + offset
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
        systemMonitorIslandOrder = order.map(\.rawValue)
    }
}
