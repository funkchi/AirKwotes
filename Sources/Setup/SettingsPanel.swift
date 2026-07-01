import SwiftUI
import AppKit

struct SettingsPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                section("General") {
                    row("Monitoring") {
                        BlueToggle(isOn: Binding(
                            get: { state.monitoringEnabled },
                            set: { state.toggleMonitoring($0) }))
                    }
                    row("Launch at login") {
                        Toggle("", isOn: Binding(
                            get: { state.launchAtLogin },
                            set: { state.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    row("Refresh every") {
                        Picker("", selection: Binding(
                            get: { state.pollingIntervalMinutes },
                            set: { state.setPollingInterval($0) })) {
                            ForEach(AppState.pollingOptions, id: \.self) { m in
                                Text(m == 1 ? "1 minute" : "\(m) minutes").tag(m)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 140)
                    }
                }

                section("Menu bar") {
                    row("Show percentage", hint: "Display the remaining % next to the ring.") {
                        Toggle("", isOn: Binding(
                            get: { state.menuBarShowsPercent },
                            set: { state.setMenuBarShowsPercent($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    row("Show provider label", hint: "Show the active provider's short name.") {
                        Toggle("", isOn: Binding(
                            get: { state.menuBarShowsLabel },
                            set: { state.setMenuBarShowsLabel($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    row("Active provider") {
                        Text(state.menuBarConfig?.label ?? "None")
                            .foregroundStyle(.secondary)
                    }
                }

                section("Alerts") {
                    row("Low-quota notifications", hint: "macOS notification when a provider drops below the threshold.") {
                        Toggle("", isOn: Binding(
                            get: { state.notificationsEnabled },
                            set: { state.setNotifications($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    row("Low-quota threshold") {
                        HStack {
                            Slider(value: Binding(
                                get: { state.lowThreshold },
                                set: { state.setLowThreshold($0) }),
                                   in: 0.05...0.9, step: 0.05)
                                .frame(width: 160)
                            Text("\(Int(state.lowThreshold * 100))%")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                section("Data") {
                    row("Manual refresh") {
                        Button {
                            Task { await state.refreshAll() }
                        } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
                            .buttonStyle(.bordered)
                            .disabled(state.isRefreshing)
                    }
                    row("Reset all data", hint: "Removes every provider and stored credential from Keychain.") {
                        Button(role: .destructive) {
                            state.resetAllData()
                        } label: { Label("Reset", systemImage: "trash") }
                            .buttonStyle(.bordered)
                    }
                }

                footer
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings").font(.system(size: 28, weight: .semibold))
            Text("Tune monitoring, the menu bar, and alerts.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fieldBG, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottom) {
                if title != "Data" { Divider().padding(.horizontal, 16) }
            }
        }
    }

    private func row<Control: View>(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Theme.accent)
            Text("AirKwotes 1.0").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let err = state.lastError {
                Text(err).font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }
}
