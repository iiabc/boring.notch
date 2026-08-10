//
//  AgentStatusView.swift
//  boringNotch
//
//  Notch UI for AI coding agent session status.
//

import SwiftUI

struct AgentExpandedActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var agentManager = AgentStatusManager.shared
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let session = agentManager.primarySession {
                HStack(spacing: 8) {
                    Image(systemName: session.tool.systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            session.state.color.gradient,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.tool.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text(session.projectName)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 10)

                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 5) {
                            if agentManager.sessions.count > 1 {
                                Text("+\(agentManager.sessions.count - 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Text(session.state.statusText)
                                .font(.subheadline)
                                .foregroundStyle(session.state.color)
                        }
                        if !detailText(for: session).isEmpty {
                            Text(detailText(for: session))
                                .font(.caption2)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                        }
                    }
                    stateIndicator(for: session.state)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            }
        }
        .frame(height: height, alignment: .center)
        .background(alignment: .bottom) {
            if let session = agentManager.primarySession {
                LinearGradient(
                    colors: [session.state.color.opacity(0.4), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: height * 0.85)
                .allowsHitTesting(false)
            }
        }
    }

    private func detailText(for session: AgentSession) -> String {
        switch session.state {
        case .done:
            return String(
                format: String(localized: "Done in %@"),
                Self.elapsedText(for: session))
        case .waiting:
            return session.label
        case .running:
            return ""
        }
    }

    @ViewBuilder
    private func stateIndicator(for state: AgentState) -> some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.blue)
        case .waiting:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: state)
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
