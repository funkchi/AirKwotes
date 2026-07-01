import SwiftUI
import AppKit

struct HeaderBar: View {
    @EnvironmentObject var state: AppState
    @Binding var sidebarTab: SetupView.SidebarTab

    var body: some View {
        HStack(spacing: 16) {
            BlueToggle(isOn: Binding(
                get: { state.monitoringEnabled },
                set: { state.toggleMonitoring($0) }))
            VStack(alignment: .leading, spacing: 2) {
                Text(accountTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Circle().fill(statusDot).frame(width: 7, height: 7)
                    Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()

            HStack(spacing: 4) {
                UtilityButton(icon: "arrow.clockwise", help: "Refresh") {
                    Task { await state.refreshAll() }
                }
                UtilityButton(icon: "ant", help: "Diagnostics") { openLogs() }
                UtilityButton(icon: "slider.horizontal.3", help: "Settings") { sidebarTab = .settings }
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text("air").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text("kwotes").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 90) // leave room for traffic lights (~70pt) on the left
        .frame(height: 64)
        .background(.white)
    }

    private var accountTitle: String {
        let n = state.configs.count
        return n == 0 ? "Not signed in" : "\(n) provider\(n == 1 ? "" : "s")"
    }
    private var statusText: String {
        if !state.monitoringEnabled { return "Paused" }
        if state.configs.isEmpty { return "Set up to begin" }
        return state.isRefreshing ? "Syncing…" : "Connected"
    }
    private var statusDot: Color {
        if !state.monitoringEnabled || state.configs.isEmpty { return .secondary }
        return state.isRefreshing ? .orange : .green
    }

    private func openLogs() {
        if let url = URL(string: "console.app") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }
}

struct UtilityButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
