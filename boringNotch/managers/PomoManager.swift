import AppKit
import Combine
import Defaults
import Foundation

enum PomoPhase: String, Codable, CaseIterable, Equatable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var compactTitle: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long Break"
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
        phase == .work ? "Focus complete" : "Break complete"
    }

    var message: String {
        phase == .work ? "Time for a break" : "Ready to focus"
    }
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
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        }
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
        advancePhase(startImmediately: true, didCompleteCurrentPhase: false)
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
        history = records
    }

    private func showCompletionNotice(for finishedPhase: PomoPhase) {
        if Defaults[.pomoSound] { NSSound.beep() }
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
