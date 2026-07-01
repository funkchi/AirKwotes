import SwiftUI
import AppKit

@main
struct AirKwotesApp: App {
    @StateObject private var state: AppState
    @StateObject private var relay: RelayManager

    init() {
        let appState = AppState()
        let relayManager = RelayManager()
        _state = StateObject(wrappedValue: appState)
        _relay = StateObject(wrappedValue: relayManager)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(state).environmentObject(relay)
                .background(SetupLauncher().environmentObject(state))
        } label: {
            MenuBarRingView()
                .environmentObject(state)
                .environmentObject(relay)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "setup") {
            SetupView()
                .environmentObject(state).environmentObject(relay)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
                .onDisappear {
                    if state.configs.isEmpty { NSApp.setActivationPolicy(.accessory) }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 660)
    }
}

/// Opens the setup window automatically on first launch (before any provider is configured).
private struct SetupLauncher: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear {
                guard !state.didCompleteSetup || state.configs.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    openWindow(id: "setup")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
