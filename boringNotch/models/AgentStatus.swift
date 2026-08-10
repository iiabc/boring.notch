//
//  AgentStatus.swift
//  boringNotch
//
//  Models for AI coding agent session status.
//

import Foundation
import SwiftUI

enum AgentTool: String, Codable {
    case claude
    case codex
    case opencode

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "opencode"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "terminal.fill"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum AgentState: String, Codable {
    case running
    case waiting
    case done

    var priority: Int {
        switch self {
        case .waiting: 2
        case .running: 1
        case .done: 0
        }
    }

    var color: Color {
        switch self {
        case .running: .blue
        case .waiting: .orange
        case .done: .green
        }
    }

    var statusText: String {
        switch self {
        case .running: String(localized: "Running")
        case .waiting: String(localized: "Needs attention")
        case .done: String(localized: "Done")
        }
    }
}

struct AgentSession: Codable, Identifiable, Equatable {
    var id: String
    var tool: AgentTool
    var state: AgentState
    var label: String
    var cwd: String
    var startedAt: TimeInterval
    var updatedAt: TimeInterval

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }

    var startedAtDate: Date { Date(timeIntervalSince1970: startedAt) }
}
