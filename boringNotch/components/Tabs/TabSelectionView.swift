//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var agentManager = AgentStatusManager.shared
    @Default(.pomoEnabled) private var pomoEnabled
    @Default(.systemMonitorEnabled) private var systemMonitorEnabled
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        var result = tabs
        if pomoEnabled {
            result.append(TabModel(label: "Pomo", icon: "timer", view: .pomo))
        }
        if Defaults[.agentStatusEnabled] && agentManager.hasActiveSessions {
            result.append(TabModel(label: "Agents", icon: "terminal", view: .agents))
        }
        if systemMonitorEnabled {
            result.append(TabModel(label: "System", icon: "chart.bar.fill", view: .system))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .onChange(of: systemMonitorEnabled) { _, isEnabled in
            if !isEnabled && coordinator.currentView == .system {
                coordinator.currentView = .home
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
