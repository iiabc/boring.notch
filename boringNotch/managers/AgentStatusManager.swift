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

    var primarySession: AgentSession? { Self.primary(of: sessions) }

    private init() {
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
        var loaded: [AgentSession] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let session = try? decoder.decode(AgentSession.self, from: data)
            else { continue }
            loaded.append(session)
        }
        apply(sessions: loaded)
    }

    private func apply(sessions newSessions: [AgentSession]) {
        let previousPrimary = Self.primary(of: sessions)
        sessions = newSessions
        notifyIfNeeded(previousPrimary: previousPrimary)
    }

    // MARK: - Notch expansion

    private var hideTask: Task<Void, Never>?

    private func notifyIfNeeded(previousPrimary: AgentSession?) {
        guard Defaults[.agentStatusEnabled] else { return }
        let coordinator = BoringViewCoordinator.shared

        // Dismiss a waiting card as soon as the session is back to running or gone.
        if coordinator.expandingView.show && coordinator.expandingView.type == .agentStatus {
            if let primary = primarySession, primary.state == .running {
                hideTask?.cancel()
                coordinator.toggleExpandingView(status: false, type: .agentStatus)
            }
        }

        guard let primary = primarySession,
            primary.state == .waiting || primary.state == .done
        else { return }

        let key = "\(primary.id)-\(primary.state.rawValue)"
        let previousKey = previousPrimary.map { "\($0.id)-\($0.state.rawValue)" }
        guard key != previousKey else { return }

        coordinator.toggleExpandingView(status: true, type: .agentStatus)

        // Done flashes briefly; waiting stays until resolved, capped at 30s.
        let timeout: TimeInterval = primary.state == .waiting ? 30 : 3
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                BoringViewCoordinator.shared.toggleExpandingView(
                    status: false, type: .agentStatus)
            }
        }
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
        let fm = FileManager.default
        guard
            let files = try? fm.contentsOfDirectory(
                at: Self.statusDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let now = Date()
        let decoder = JSONDecoder()
        var removedAny = false
        for url in files where url.pathExtension == "json" {
            let modified =
                (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? now
            let age = now.timeIntervalSince(modified)
            var shouldDelete = age > 6 * 3600
            if !shouldDelete, let data = try? Data(contentsOf: url),
                let session = try? decoder.decode(AgentSession.self, from: data)
            {
                shouldDelete = session.state == .done && age > 20
            }
            if shouldDelete {
                try? fm.removeItem(at: url)
                removedAny = true
            }
        }
        if removedAny { rescan() }
    }
}
