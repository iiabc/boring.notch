//
//  AgentStatusManager.swift
//  boringNotch
//
//  Watches ~/.boringnotch/agents for status files written by Claude Code
//  hooks and the opencode plugin, and surfaces them in the notch.
//

import Defaults
import Foundation
import SwiftUI

@MainActor
class AgentStatusManager: ObservableObject {
    static let shared = AgentStatusManager()

    @Published private(set) var sessions: [AgentSession] = []

    private var directorySource: DispatchSourceFileSystemObject?
    private var rescanTask: Task<Void, Never>?
    private var cleanupTimer: Timer?
    private var notificationSessionID: String?

    nonisolated static let statusDirectory: URL =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boringnotch/agents", isDirectory: true)

    var hasActiveSessions: Bool { !sessions.isEmpty }

    static func primary(of sessions: [AgentSession]) -> AgentSession? {
        sessions.max { lhs, rhs in
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority < rhs.state.priority
            }
            return lhs.updatedAt < rhs.updatedAt
        }
    }

    var primarySession: AgentSession? {
        if let recentDone = sessions
            .filter({ $0.state == .done })
            .max(by: { $0.updatedAt < $1.updatedAt }),
            Date().timeIntervalSince1970 - recentDone.updatedAt <= Self.doneRetention
        {
            return recentDone
        }
        return Self.primary(of: sessions)
    }

    private static let doneRetention: TimeInterval = 20
    private static let codexRunningRetention: TimeInterval = 5 * 60
    private static let otherRunningRetention: TimeInterval = 6 * 3600

    private init() {
        AgentHookInstaller.refreshInstalledHookScript()
        try? FileManager.default.createDirectory(
            at: Self.statusDirectory, withIntermediateDirectories: true)
        startWatching()
        startCleanupTimer()
        rescan()
    }

    // MARK: - Directory watching

    private func startWatching() {
        let fd = open(Self.statusDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleRescan()
            }
        }
        source.setCancelHandler { close(fd) }
        directorySource = source
        source.resume()
    }

    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    func rescan() {
        let fm = FileManager.default
        guard
            let files = try? fm.contentsOfDirectory(
                at: Self.statusDirectory, includingPropertiesForKeys: nil)
        else {
            apply(sessions: [])
            return
        }
        let decoder = JSONDecoder()
        let now = Date().timeIntervalSince1970
        var loaded: [AgentSession] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let session = try? decoder.decode(AgentSession.self, from: data)
            else { continue }
            if Self.isStale(session, now: now) {
                try? fm.removeItem(at: url)
                continue
            }
            loaded.append(session)
        }
        apply(sessions: loaded)
    }

    private static func isStale(_ session: AgentSession, now: TimeInterval) -> Bool {
        let age = max(0, now - session.updatedAt)
        switch session.state {
        case .done:
            return age > doneRetention
        case .waiting:
            return age > otherRunningRetention
        case .running:
            let retention = session.tool == .codex
                ? codexRunningRetention : otherRunningRetention
            return age > retention
        }
    }

    private func apply(sessions newSessions: [AgentSession]) {
        let previousSessions = sessions
        sessions = newSessions
        if newSessions.isEmpty, BoringViewCoordinator.shared.currentView == .agents {
            BoringViewCoordinator.shared.currentView = .home
        }
        notifyIfNeeded(previousSessions: previousSessions)
    }

    // MARK: - Notch expansion

    private var hideTask: Task<Void, Never>?

    private func notifyIfNeeded(previousSessions: [AgentSession]) {
        guard Defaults[.agentStatusEnabled] else { return }
        let coordinator = BoringViewCoordinator.shared

        // Dismiss a waiting card as soon as the session is back to running or gone.
        if let notificationSessionID,
            coordinator.expandingView.show && coordinator.expandingView.type == .agentStatus
        {
            let session = newSession(withID: notificationSessionID)
            if session == nil || session?.state == .running {
                hideTask?.cancel()
                self.notificationSessionID = nil
                coordinator.toggleExpandingView(status: false, type: .agentStatus)
            }
        }

        let previousStates = Dictionary(
            uniqueKeysWithValues: previousSessions.map { ($0.id, $0.state) })
        guard let changedSession = sessions
            .filter({ $0.state == .waiting || $0.state == .done })
            .filter({ previousStates[$0.id] != $0.state })
            .max(by: { $0.updatedAt < $1.updatedAt })
        else { return }

        coordinator.toggleExpandingView(status: true, type: .agentStatus)
        notificationSessionID = changedSession.id

        // Done flashes briefly; waiting stays until resolved, capped at 30s.
        let timeout: TimeInterval = changedSession.state == .waiting ? 30 : 3
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.notificationSessionID = nil
                BoringViewCoordinator.shared.toggleExpandingView(
                    status: false, type: .agentStatus)
            }
        }
    }

    private func newSession(withID id: String) -> AgentSession? {
        sessions.first(where: { $0.id == id })
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleFiles()
            }
        }
    }

    private func cleanupStaleFiles() {
        rescan()
    }
}
