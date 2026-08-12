import AppKit
import Combine
import Darwin
import Foundation

struct SystemVolumeStatus: Identifiable, Equatable {
    let id: String
    let name: String
    let mountPoint: String
    let totalBytes: UInt64
    let availableBytes: UInt64
    let purgeableBytes: UInt64

    var usedBytes: UInt64 {
        totalBytes > availableBytes ? totalBytes - availableBytes : 0
    }

    var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

@MainActor
final class SystemMonitorManager: ObservableObject {
    static let shared = SystemMonitorManager()

    private let resourceRefreshInterval: TimeInterval = 1
    private let storageRefreshInterval: TimeInterval = 30

    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var cpuCoreCount: Int = ProcessInfo.processInfo.processorCount
    @Published private(set) var usedMemoryBytes: UInt64 = 0
    @Published private(set) var totalMemoryBytes: UInt64 = UInt64(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var internalStorage = SystemVolumeStatus(
        id: "/",
        name: "Macintosh HD",
        mountPoint: "/",
        totalBytes: 0,
        availableBytes: 0,
        purgeableBytes: 0
    )
    @Published private(set) var externalVolumes: [SystemVolumeStatus] = []
    @Published private(set) var networkDownloadRate: Double = 0
    @Published private(set) var networkUploadRate: Double = 0
    @Published private(set) var networkPeakRate: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var networkHistory: [Double] = []
    @Published private(set) var loadAverage1m: Double = 0
    @Published private(set) var loadAverage5m: Double = 0

    private let historyLimit = 60

    private var refreshTimer: Timer?
    private var storageRefreshTimer: Timer?
    private var mountObservers: [NSObjectProtocol] = []
    private var previousCPUTotalTicks: UInt64 = 0
    private var previousCPUActiveTicks: UInt64 = 0
    private var previousNetworkDownloadBytes: UInt64 = 0
    private var previousNetworkUploadBytes: UInt64 = 0
    private var previousNetworkSampleDate: Date?

    private init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for notification in [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification
        ] {
            mountObservers.append(
                workspaceCenter.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshStorage()
                    }
                }
            )
        }
    }

    deinit {
        for observer in mountObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func startMonitoring() {
        guard refreshTimer == nil else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: resourceRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshResourceUsage()
            }
        }
        storageRefreshTimer = Timer.scheduledTimer(withTimeInterval: storageRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStorage()
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        storageRefreshTimer?.invalidate()
        storageRefreshTimer = nil
    }

    func refresh() {
        refreshResourceUsage()
        refreshStorage()
    }

    private func refreshResourceUsage() {
        let cpu = readCPUUsage()
        let memory = Self.readMemoryUsage()
        let network = readNetworkRates()

        cpuCoreCount = cpu.coreCount
        cpuUsage = cpu.usage
        usedMemoryBytes = memory.usedBytes
        totalMemoryBytes = memory.totalBytes
        networkDownloadRate = network.download
        networkUploadRate = network.upload
        let currentPeak = max(network.download, network.upload)
        networkPeakRate = max(currentPeak, networkPeakRate * 0.95, 1_024)

        let memoryUsage = memory.totalBytes > 0
            ? min(1, max(0, Double(memory.usedBytes) / Double(memory.totalBytes)))
            : 0
        appendHistory(value: cpu.usage, to: &cpuHistory)
        appendHistory(value: memoryUsage, to: &memoryHistory)
        appendHistory(value: network.download, to: &networkHistory)

        var loadAverages = [Double](repeating: 0, count: 2)
        if getloadavg(&loadAverages, 2) == 2 {
            loadAverage1m = loadAverages[0]
            loadAverage5m = loadAverages[1]
        }
    }

    private func appendHistory(value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private func readNetworkRates() -> (download: Double, upload: Double) {
        let counters = Self.readNetworkCounters()
        let now = Date()
        defer {
            previousNetworkDownloadBytes = counters.download
            previousNetworkUploadBytes = counters.upload
            previousNetworkSampleDate = now
        }

        guard let previousDate = previousNetworkSampleDate else {
            return (networkDownloadRate, networkUploadRate)
        }

        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0,
              counters.download >= previousNetworkDownloadBytes,
              counters.upload >= previousNetworkUploadBytes else {
            return (0, 0)
        }

        return (
            Double(counters.download - previousNetworkDownloadBytes) / elapsed,
            Double(counters.upload - previousNetworkUploadBytes) / elapsed
        )
    }

    private static func readNetworkCounters() -> (download: UInt64, upload: UInt64) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
            return (0, 0)
        }
        defer { freeifaddrs(addresses) }

        var download: UInt64 = 0
        var upload: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            let name = String(cString: interface.pointee.ifa_name)
            if name.hasPrefix("en"),
               let address = interface.pointee.ifa_addr,
               Int32(address.pointee.sa_family) == AF_LINK,
               let data = interface.pointee.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                download += UInt64(counters.ifi_ibytes)
                upload += UInt64(counters.ifi_obytes)
            }
            cursor = interface.pointee.ifa_next
        }
        return (download, upload)
    }

    private func refreshStorage() {
        let storage = Self.readStorage()
        internalStorage = storage.internalVolume
        externalVolumes = storage.externalVolumes
    }

    private func readCPUUsage() -> (usage: Double, coreCount: Int) {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else {
            return (cpuUsage, Int(ProcessInfo.processInfo.processorCount))
        }

        defer {
            let size = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: processorInfo), size)
        }

        var activeTicks: UInt64 = 0
        var totalTicks: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)

        for processor in 0..<Int(processorCount) {
            let offset = processor * stride
            let user = UInt64(processorInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(processorInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(processorInfo[offset + Int(CPU_STATE_NICE)])
            let idle = UInt64(processorInfo[offset + Int(CPU_STATE_IDLE)])
            activeTicks += user + system + nice
            totalTicks += user + system + nice + idle
        }

        let totalDelta = totalTicks >= previousCPUTotalTicks
            ? totalTicks - previousCPUTotalTicks
            : 0
        let activeDelta = activeTicks >= previousCPUActiveTicks
            ? activeTicks - previousCPUActiveTicks
            : 0

        previousCPUTotalTicks = totalTicks
        previousCPUActiveTicks = activeTicks

        guard totalDelta > 0 else {
            return (cpuUsage, Int(processorCount))
        }

        return (
            min(1, max(0, Double(activeDelta) / Double(totalDelta))),
            Int(processorCount)
        )
    }

    private static func readMemoryUsage() -> (usedBytes: UInt64, totalBytes: UInt64) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = UInt64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else {
            return (0, totalBytes)
        }

        let availablePages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        let availableBytes = availablePages * UInt64(vm_kernel_page_size)
        return (totalBytes > availableBytes ? totalBytes - availableBytes : 0, totalBytes)
    }

    private static func readStorage() -> (
        internalVolume: SystemVolumeStatus,
        externalVolumes: [SystemVolumeStatus]
    ) {
        let internalURL = URL(fileURLWithPath: "/")
        let internalVolume = volumeStatus(for: internalURL) ?? SystemVolumeStatus(
            id: "/",
            name: "Macintosh HD",
            mountPoint: "/",
            totalBytes: 0,
            availableBytes: 0,
            purgeableBytes: 0
        )

        let resourceKeys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ]

        let externalVolumes = FileManager.default
            .mountedVolumeURLs(includingResourceValuesForKeys: Array(resourceKeys), options: [.skipHiddenVolumes])?
            .compactMap { url -> SystemVolumeStatus? in
                guard url.path != "/" else { return nil }
                guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
                let isExternal = values.volumeIsInternal == false
                    || values.volumeIsRemovable == true
                    || values.volumeIsEjectable == true
                guard isExternal else { return nil }
                return volumeStatus(for: url, values: values)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []

        return (internalVolume, externalVolumes)
    }

    private static func volumeStatus(for url: URL) -> SystemVolumeStatus? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return volumeStatus(for: url, values: values)
    }

    private static func volumeStatus(
        for url: URL,
        values: URLResourceValues
    ) -> SystemVolumeStatus? {
        guard let totalCapacity = values.volumeTotalCapacity, totalCapacity > 0 else {
            return nil
        }

        let availableCapacity = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        let freeCapacity = Int64(values.volumeAvailableCapacity ?? 0)
        let purgeableCapacity = max(0, availableCapacity - freeCapacity)
        let name = values.volumeName?.isEmpty == false
            ? values.volumeName!
            : url.lastPathComponent

        return SystemVolumeStatus(
            id: url.path,
            name: name,
            mountPoint: url.path,
            totalBytes: UInt64(totalCapacity),
            availableBytes: UInt64(max(0, availableCapacity)),
            purgeableBytes: UInt64(max(0, purgeableCapacity))
        )
    }
}
