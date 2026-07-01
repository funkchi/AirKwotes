import SwiftUI

struct Sidebar: View {
    @Binding var tab: SetupView.SidebarTab
    @Binding var selectedID: UUID?
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.menuBarConfig?.label ?? "None")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Menu bar provider")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)

            VStack(alignment: .leading, spacing: 4) {
                navItem(.providers, icon: "cpu")
                navItem(.relay, icon: "bolt.horizontal")
                navItem(.settings, icon: "slider.horizontal.3")
            }
            .padding(.horizontal, 12)

            Spacer()

            if let worst = state.lowOrCritical.first {
                let snap = state.snapshots[worst.id] ?? QuotaSnapshot.empty
                WarningCard(
                    title: "Low quota — \(worst.label)",
                    message: "Only \(snap.remainingDisplay) remaining. Top up to keep requests running.")
                    .padding(16)
            } else if let prob = state.problems.first {
                let snap = state.snapshots[prob.id] ?? QuotaSnapshot.empty
                WarningCard(
                    title: "Connection failed",
                    message: "\(prob.label): \(statusText(snap.status))")
                    .padding(16)
            }
        }
        .frame(width: 240)
        .background(Theme.sidebar)
    }

    private func navItem(_ t: SetupView.SidebarTab, icon: String) -> some View {
        Button {
            tab = t
            if t == .providers, selectedID == nil { selectedID = state.menuBarProviderID }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent)
                Text(t.rawValue).font(.subheadline.weight(tab == t ? .semibold : .regular))
                    .foregroundStyle(tab == t ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(tab == t ? Color.white.opacity(0.7) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ s: QuotaSnapshot.Status) -> String {
        switch s {
        case .invalid: return "invalid API key"
        case .unsupported: return "quota not available"
        case .error(let m): return m
        default: return "check key"
        }
    }
}
