//
//  AgentStatusView.swift
//  boringNotch
//
//  Notch UI for AI coding agent session status.
//

import SwiftUI

struct AgentSneakPeekLine: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: session.tool.systemImage)
            GeometryReader { geo in
                MarqueeText(
                    summaryText,
                    color: session.state == .waiting ? .orange : .gray,
                    delayDuration: 1.0,
                    frameWidth: geo.size.width
                )
            }
        }
        .foregroundStyle(session.state == .waiting ? .orange : .gray)
        .padding(.bottom, 10)
    }

    private var summaryText: String {
        let base = "\(session.tool.displayName) · \(session.projectName)"
        switch session.state {
        case .waiting:
            return session.label.isEmpty
                ? "\(base) — \(session.state.statusText)"
                : "\(base) — \(session.label)"
        case .done:
            return "\(base) — Done in \(Self.elapsedText(for: session))"
        case .running:
            return base
        }
    }

    static func elapsedText(for session: AgentSession) -> String {
        let seconds = max(0, Int(session.updatedAt - session.startedAt))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(seconds % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
