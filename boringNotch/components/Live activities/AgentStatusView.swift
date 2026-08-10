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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
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
                        detailText(for: session)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    stateIndicator(for: session.state)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            }
        }
        .frame(height: height, alignment: .center)
    }

    @ViewBuilder
    private func detailText(for session: AgentSession) -> some View {
        if !session.label.isEmpty {
            Text(session.label)
        } else {
            Text(timerInterval: session.startedAtDate...Date.distantFuture)
                .monospacedDigit()
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
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

struct AgentClosedActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var agentManager = AgentStatusManager.shared
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let session = agentManager.primarySession {
                Image(systemName: session.tool.systemImage)
                    .font(.system(size: max(9, height - 20), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(
                        width: max(0, height - 12),
                        height: max(0, height - 12)
                    )

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 4 + (2 * liveActivityEdgeMargin))

                stateDot(session.state)
                    .frame(
                        width: max(0, height - 12),
                        height: max(0, height - 12)
                    )
            }
        }
        .frame(height: height, alignment: .center)
    }

    @ViewBuilder
    private func stateDot(_ state: AgentState) -> some View {
        let dot = Circle()
            .fill(state.color)
            .frame(width: 8, height: 8)
        if state == .done {
            dot
        } else {
            dot
                .phaseAnimator([0.35, 1.0]) { content, opacity in
                    content.opacity(opacity)
                }
        }
    }
}
