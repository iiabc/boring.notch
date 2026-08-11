import AppKit
import Combine
import Defaults
import Foundation
import UniformTypeIdentifiers

enum PomoPhase: String, Codable, CaseIterable, Equatable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }

    var compactTitle: String {
        switch self {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }

    var symbolName: String {
        switch self {
        case .work: return "timer"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "bed.double.fill"
        }
    }
}

enum PomoPreset: String, CaseIterable, Identifiable, Hashable {
    case classic
    case deepWork
    case shortCycle
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: return String(localized: "Classic")
        case .deepWork: return String(localized: "Deep Work")
        case .shortCycle: return String(localized: "Short Cycle")
        case .custom: return String(localized: "Custom")
        }
    }

    var configuration: (work: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval, interval: Int)? {
        switch self {
        case .classic:
            return (25 * 60, 5 * 60, 15 * 60, 4)
        case .deepWork:
            return (50 * 60, 10 * 60, 30 * 60, 4)
        case .shortCycle:
            return (15 * 60, 3 * 60, 10 * 60, 4)
        case .custom:
            return nil
        }
    }

    static func matching(
        work: TimeInterval,
        shortBreak: TimeInterval,
        longBreak: TimeInterval,
        interval: Int
    ) -> PomoPreset {
        allCases.first {
            guard let configuration = $0.configuration else { return false }
            return configuration.work == work
                && configuration.shortBreak == shortBreak
                && configuration.longBreak == longBreak
                && configuration.interval == interval
        } ?? .custom
    }
}

enum PomoStatus: String, Codable {
    case idle
    case running
    case paused
}

struct PomoSessionRecord: Codable, Identifiable {
    let id: UUID
    let phase: PomoPhase
    let duration: TimeInterval
    let completedAt: Date
    let taskTitle: String
}

struct PomoCompletionNotice: Equatable {
    let phase: PomoPhase

    var title: String {
        phase == .work ? String(localized: "Focus complete") : String(localized: "Break complete")
    }

    var message: String {
        phase == .work ? String(localized: "Time for a break") : String(localized: "Ready to focus")
    }
}

struct PomoHistoryExport: Codable {
    let version: Int
    let exportedAt: Date
    let sessions: [PomoSessionRecord]
}

private struct PersistedPomoState: Codable {
    let phase: PomoPhase
    let status: PomoStatus
    let duration: TimeInterval
    let remaining: TimeInterval
    let endDate: Date?
    let completedWorkSessions: Int
    let taskTitle: String
}

@MainActor
final class PomoManager: ObservableObject {
    static let shared = PomoManager()

    @Published private(set) var phase: PomoPhase = .work
    @Published private(set) var status: PomoStatus = .idle
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var completedWorkSessions: Int = 0
    @Published private(set) var taskTitle = ""
    @Published private(set) var history: [PomoSessionRecord] = []
    @Published private(set) var completionRevision = 0
    @Published private(set) var completionNotice: PomoCompletionNotice?
    @Published private(set) var dataStatusMessage: String?

    private var endDate: Date?
    private var ticker: Task<Void, Never>?
    private var completionNoticeTask: Task<Void, Never>?

    private let stateKey = "pomo.persistedState"
    private let historyKey = "pomo.sessionHistory"

    var isActive: Bool { status != .idle }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining / duration, 0), 1)
    }

    var statusTitle: String {
        switch status {
        case .idle: return String(localized: "Ready")
        case .running: return String(localized: "Running")
        case .paused: return String(localized: "Paused")
        }
    }

    var dailyGoal: Int { max(Defaults[.pomoDailyGoal], 1) }

    var todayFocusSessions: Int {
        focusRecords(in: todayInterval).count
    }

    var todayFocusMinutes: Int {
        focusMinutes(in: todayInterval)
    }

    var weekFocusSessions: Int {
        focusRecords(in: weekInterval).count
    }

    var weekFocusMinutes: Int {
        focusMinutes(in: weekInterval)
    }

    var dailyGoalProgress: Double {
        min(Double(todayFocusSessions) / Double(dailyGoal), 1)
    }

    var recentHistory: [PomoSessionRecord] {
        Array(history.prefix(6))
    }

    private init() {
        loadHistory()
        loadState()
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        guard status == .running, let endDate else { return max(remaining, 0) }
        return max(endDate.timeIntervalSince(date), 0)
    }

    func toggle() {
        if status == .running {
            pause()
        } else {
            start()
        }
    }

    func start() {
        guard status != .running else { return }
        if status == .idle {
            duration = configuredDuration(for: phase)
            remaining = min(max(remaining, 0), duration)
            if remaining == 0 { remaining = duration }
        }

        endDate = Date().addingTimeInterval(remaining)
        status = .running
        saveState()
        startTicker()
    }

    func pause() {
        guard status == .running else { return }
        let previousCompletionRevision = completionRevision
        updateClock()
        guard completionRevision == previousCompletionRevision else { return }
        status = .paused
        endDate = nil
        saveState()
    }

    func stop() {
        stopTicker()
        phase = .work
        status = .idle
        duration = configuredDuration(for: .work)
        remaining = duration
        endDate = nil
        completedWorkSessions = 0
        taskTitle = ""
        completionNoticeTask?.cancel()
        completionNoticeTask = nil
        completionNotice = nil
        saveState()
    }

    func resetCurrentPhase() {
        stopTicker()
        status = .idle
        duration = configuredDuration(for: phase)
        remaining = duration
        completionNoticeTask?.cancel()
        completionNoticeTask = nil
        completionNotice = nil
        endDate = nil
        saveState()
    }

    func skip() {
        let previousCompletionRevision = completionRevision
        if status == .running { updateClock() }
        guard completionRevision == previousCompletionRevision else { return }
        let skippedPhase = phase
        advancePhase(startImmediately: true, didCompleteCurrentPhase: false)
        showCompletionNotice(for: skippedPhase, playSound: false)
    }

    func addMinute() {
        if status == .running {
            let previousCompletionRevision = completionRevision
            updateClock()
            guard completionRevision == previousCompletionRevision else { return }
        }
        duration += 60
        remaining += 60
        if status == .running {
            endDate = Date().addingTimeInterval(remaining)
        }
        saveState()
    }

    func updateTaskTitle(_ title: String) {
        taskTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        saveState()
    }

    func refreshConfiguration() {
        guard status == .idle else { return }
        duration = configuredDuration(for: phase)
        remaining = duration
        saveState()
    }

    func applyPreset(_ preset: PomoPreset) {
        guard let configuration = preset.configuration else { return }
        Defaults[.pomoWorkDuration] = configuration.work
        Defaults[.pomoShortBreakDuration] = configuration.shortBreak
        Defaults[.pomoLongBreakDuration] = configuration.longBreak
        Defaults[.pomoLongBreakInterval] = configuration.interval
        refreshConfiguration()
    }

    func clearHistory() {
        history = []
        persistHistory()
        dataStatusMessage = String(localized: "Pomodoro history cleared")
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Pomodoro data")
        panel.nameFieldStringValue = "pomodoro-history.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let archive = PomoHistoryExport(version: 1, exportedAt: .now, sessions: history)
            try encoder.encode(archive).write(to: url, options: .atomic)
            dataStatusMessage = String(localized: "Pomodoro data exported")
        } catch {
            dataStatusMessage = String(localized: "Could not export Pomodoro data")
        }
    }

    func importHistory() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Pomodoro data")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: url)
            let importedSessions: [PomoSessionRecord]

            if let archive = try? decoder.decode(PomoHistoryExport.self, from: data) {
                importedSessions = archive.sessions
            } else {
                importedSessions = try decoder.decode([PomoSessionRecord].self, from: data)
            }

            var recordsByID = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
            importedSessions.forEach { recordsByID[$0.id] = $0 }
            history = Array(recordsByID.values)
                .sorted { $0.completedAt > $1.completedAt }
                .prefix(100)
                .map { $0 }
            persistHistory()
            dataStatusMessage = String(localized: "Pomodoro data imported")
        } catch {
            dataStatusMessage = String(localized: "Could not import Pomodoro data")
        }
    }

    func formattedRemaining(at date: Date = .now) -> String {
        Self.formatTime(remaining(at: date))
    }

    static func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.up)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func configuredDuration(for phase: PomoPhase) -> TimeInterval {
        switch phase {
        case .work: return Defaults[.pomoWorkDuration]
        case .shortBreak: return Defaults[.pomoShortBreakDuration]
        case .longBreak: return Defaults[.pomoLongBreakDuration]
        }
    }

    private func nextPhase(didCompleteCurrentPhase: Bool) -> PomoPhase {
        switch phase {
        case .work:
            guard didCompleteCurrentPhase else { return .shortBreak }
            let interval = max(Defaults[.pomoLongBreakInterval], 1)
            return completedWorkSessions % interval == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }

    private func updateClock() {
        guard status == .running else { return }
        remaining = remaining(at: .now)
        if remaining <= 0 {
            completeCurrentPhase()
        }
    }

    private func completeCurrentPhase() {
        let finishedPhase = phase
        let finishedDuration = duration
        if finishedPhase == .work {
            completedWorkSessions += 1
            recordSession(phase: finishedPhase, duration: finishedDuration)
        } else {
            recordSession(phase: finishedPhase, duration: finishedDuration)
        }

        completionRevision += 1
        showCompletionNotice(for: finishedPhase)
        advancePhase(
            startImmediately: Defaults[.pomoAutoStartNext],
            didCompleteCurrentPhase: finishedPhase == .work
        )
    }

    private func advancePhase(startImmediately: Bool, didCompleteCurrentPhase: Bool) {
        phase = nextPhase(didCompleteCurrentPhase: didCompleteCurrentPhase)
        duration = configuredDuration(for: phase)
        remaining = duration
        endDate = startImmediately ? Date().addingTimeInterval(remaining) : nil
        status = startImmediately ? .running : .idle
        if !startImmediately { stopTicker() } else { startTicker() }
        saveState()
    }

    private func recordSession(phase: PomoPhase, duration: TimeInterval) {
        let record = PomoSessionRecord(
            id: UUID(),
            phase: phase,
            duration: duration,
            completedAt: .now,
            taskTitle: taskTitle
        )
        history.insert(record, at: 0)
        history = Array(history.prefix(100))
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.updateClock()
                self?.saveState()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func saveState() {
        let state = PersistedPomoState(
            phase: phase,
            status: status,
            duration: duration,
            remaining: remaining(at: .now),
            endDate: status == .running ? endDate : nil,
            completedWorkSessions: completedWorkSessions,
            taskTitle: taskTitle
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(PersistedPomoState.self, from: data)
        else {
            duration = configuredDuration(for: .work)
            remaining = duration
            return
        }

        phase = state.phase
        status = state.status
        duration = state.duration
        remaining = state.remaining
        endDate = state.endDate
        completedWorkSessions = state.completedWorkSessions
        taskTitle = state.taskTitle

        if status == .running {
            if endDate == nil {
                endDate = Date().addingTimeInterval(max(remaining, 0))
            }
            if remaining(at: .now) <= 0 {
                completeCurrentPhase()
            } else {
                startTicker()
            }
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([PomoSessionRecord].self, from: data)
        else { return }
        history = Array(records.sorted { $0.completedAt > $1.completedAt }.prefix(100))
    }

    private var todayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: .now, duration: 0)
    }

    private var weekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)
            ?? todayInterval
    }

    private func focusRecords(in interval: DateInterval) -> [PomoSessionRecord] {
        history.filter { $0.phase == .work && interval.contains($0.completedAt) }
    }

    private func focusMinutes(in interval: DateInterval) -> Int {
        Int(focusRecords(in: interval).reduce(0) { $0 + $1.duration } / 60)
    }

    private func showCompletionNotice(for finishedPhase: PomoPhase, playSound: Bool = true) {
        if playSound && Defaults[.pomoSound] { NSSound.beep() }
        guard Defaults[.pomoNotchNotifications] else { return }

        completionNoticeTask?.cancel()
        completionNotice = PomoCompletionNotice(phase: finishedPhase)
        completionNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.completionNotice = nil
            self?.completionNoticeTask = nil
        }
    }
}
