//
//  AgentSettingsView.swift
//  boringNotch
//
//  Settings for AI coding agent (Claude Code / opencode) status integration.
//

import Defaults
import SwiftUI

struct AgentSettings: View {
    @ObservedObject var agentManager = AgentStatusManager.shared

    @State private var claudeInstalled = AgentHookInstaller.isClaudeInstalled()
    @State private var openCodeInstalled = AgentHookInstaller.isOpenCodeInstalled()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .agentStatusEnabled) {
                    Text("Show agent status in the notch")
                }
            }

            Section {
                integrationRow(
                    name: "Claude Code",
                    systemImage: "sparkle",
                    installed: claudeInstalled,
                    install: { try AgentHookInstaller.installClaude() },
                    uninstall: { try AgentHookInstaller.uninstallClaude() }
                )
                integrationRow(
                    name: "opencode",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    installed: openCodeInstalled,
                    install: { try AgentHookInstaller.installOpenCode() },
                    uninstall: { try AgentHookInstaller.uninstallOpenCode() }
                )
            } header: {
                Text("Integrations")
            }

            Section {
                if agentManager.sessions.isEmpty {
                    Text("No active sessions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(agentManager.sessions) { session in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(session.state.color)
                                .frame(width: 8, height: 8)
                            Text(session.tool.displayName)
                            Text(session.projectName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(session.state.statusText)
                                .foregroundStyle(session.state.color)
                        }
                    }
                }
            } header: {
                Text("Active Sessions")
            }
        }
        .alert(
            "Agent Integration", isPresented: errorBinding,
            actions: {
                Button("OK") { errorMessage = nil }
            },
            message: {
                Text(errorMessage ?? "")
            })
        .accentColor(.effectiveAccent)
        .navigationTitle("Agents")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @ViewBuilder
    private func integrationRow(
        name: String,
        systemImage: String,
        installed: Bool,
        install: @escaping () throws -> Void,
        uninstall: @escaping () throws -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 20)
            Text(name)
            Spacer()
            if installed {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button("Remove") {
                    run(uninstall)
                }
            }
            Button(installed ? "Reinstall" : "Install") {
                run(install)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
        claudeInstalled = AgentHookInstaller.isClaudeInstalled()
        openCodeInstalled = AgentHookInstaller.isOpenCodeInstalled()
        agentManager.rescan()
    }
}
