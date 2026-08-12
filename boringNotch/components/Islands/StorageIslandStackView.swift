import SwiftUI

struct StorageIslandStackView: View {
    @ObservedObject var monitor: SystemMonitorManager
    @AppStorage("storageIslandTopVolumeID") private var topVolumeID: String = "/"
    @State private var order: [String] = ["/"]

    private var volumes: [SystemVolumeStatus] {
        [monitor.internalStorage] + monitor.externalVolumes
    }

    private var volumeIDs: [String] {
        volumes.map(\.id)
    }

    private var orderedVolumes: [SystemVolumeStatus] {
        let byID = Dictionary(uniqueKeysWithValues: volumes.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    var body: some View {
        ZStack(alignment: .top) {
            stackCards
        }
        .animation(.spring(duration: 0.55, bounce: 0.25), value: order)
        .contentShape(Rectangle())
        .onTapGesture { cycleStack() }
        .onAppear(perform: reconcileOrder)
        .onChange(of: volumeIDs) { reconcileOrder() }
    }

    @ViewBuilder
    private var stackCards: some View {
        let stack = orderedVolumes
        ForEach(Array(stack.enumerated().reversed()), id: \.element.id) { index, volume in
            cardView(volume: volume, index: index)
        }
    }

    private func cardView(volume: SystemVolumeStatus, index: Int) -> some View {
        MetricIslandView.storage(volume: volume)
            .frame(height: 108)
            .scaleEffect(index == 0 ? 1 : max(0.9, 1 - 0.035 * CGFloat(index)), anchor: .top)
            .offset(y: index == 0 ? 0 : 10 * CGFloat(min(index, 2)))
            .opacity(index > 2 ? 0 : 1)
            .zIndex(-Double(index))
            .allowsHitTesting(index == 0)
    }

    private func cycleStack() {
        guard order.count > 1 else { return }
        withAnimation(.spring(duration: 0.55, bounce: 0.25)) {
            order.append(order.removeFirst())
        }
        topVolumeID = order.first ?? "/"
    }

    private func reconcileOrder() {
        let ids = volumes.map(\.id)
        guard !ids.isEmpty else { return }
        var next = order.filter { ids.contains($0) }
        next.append(contentsOf: ids.filter { !next.contains($0) })
        if let front = next.first, front != topVolumeID, ids.contains(topVolumeID),
           let storedIndex = next.firstIndex(of: topVolumeID) {
            next.insert(next.remove(at: storedIndex), at: 0)
        }
        if next != order {
            order = next
        }
        if let front = order.first, front != topVolumeID {
            topVolumeID = front
        }
    }
}
