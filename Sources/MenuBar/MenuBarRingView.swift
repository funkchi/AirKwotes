import SwiftUI
import AppKit

struct MenuBarRingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let snap = state.menuBarSnapshot
        HStack(spacing: 4) {
            Image(nsImage: MenuBarRingImage.make(percent: snap.remainingPercent, status: snap.status))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            if state.menuBarShowsLabel, let cfg = state.menuBarConfig {
                Text(cfg.label).font(.system(size: 11, weight: .medium))
            }
            if state.menuBarShowsPercent, let p = snap.remainingPercent {
                Text(Format.percent(p)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
        }
        .accessibilityLabel("AirKwotes quota")
        .accessibilityValue(accessibilityValue(snap))
        .help(tooltip(snap))
        .onAppear { state.startTimer() }
    }

    private func tooltip(_ snap: QuotaSnapshot) -> String {
        guard let cfg = state.menuBarConfig else { return "AirKwotes — no provider" }
        let head = "\(cfg.label): \(snap.remainingDisplay)"
        if let p = snap.remainingPercent { return "\(head) (\(Format.percent(p)) remaining)" }
        return head
    }

    private func accessibilityValue(_ snap: QuotaSnapshot) -> String {
        if let p = snap.remainingPercent { return "\(Format.percent(p)) remaining" }
        return snap.remainingDisplay
    }
}

#if DEBUG
#Preview {
    MenuBarRingView().environmentObject({
        let s = AppState(); return s
    }())
}
#endif
