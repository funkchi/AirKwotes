import SwiftUI
import AppKit

struct MenuPopoverView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var relay: RelayManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    relayRow
                    ForEach(state.configs) { cfg in
                        ProviderRow(config: cfg)
                    }
                    if state.configs.isEmpty {
                        emptyState
                    }
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 420)
        .background(.regularMaterial)
        .task {
            state.startTimer()
            await state.refreshAll()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AirKwotes").font(.headline)
                Text(state.monitoringEnabled ? "Monitoring" : "Paused")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await state.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.isRefreshing)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.horizontal").font(.title2).foregroundStyle(.secondary)
            Text("No providers yet").font(.subheadline).foregroundStyle(.secondary)
            Button("Set Up…") { openWindow(id: "setup") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var relayRow: some View {
        let failed = !relay.serverOn && relay.lastError != nil
        return HStack(spacing: 10) {
            Image(systemName: relay.serverOn ? "bolt.horizontal.fill" : "bolt.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(relay.serverOn ? Theme.accent : (failed ? .red : .secondary))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Relay").font(.subheadline.weight(.semibold))
                if failed, let err = relay.lastError {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else {
                    Text(relay.serverOn ? "ON · 127.0.0.1:\(relay.port)" : "OFF")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if relay.serverOn {
                Button {
                    relay.setServerOn(false)
                } label: {
                    Text("Stop").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button {
                    relay.setServerOn(true)
                } label: {
                    Text("Connect").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "setup")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label("Manage", systemImage: "slider.horizontal.3") }
                .buttonStyle(.bordered)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(10)
    }
}

private struct ProviderRow: View {
    let config: ProviderConfig
    @EnvironmentObject var state: AppState

    var body: some View {
        let snap = state.snapshots[config.id] ?? QuotaSnapshot.empty
        let isMenuBar = state.menuBarProviderID == config.id
        let pending = state.isPendingReminder(config)
        HStack(spacing: 10) {
            Ring(remaining: snap.remainingPercent, status: snap.status,
                 size: 30, lineWidth: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.label).font(.subheadline.weight(.semibold))
                    if isMenuBar {
                        Text("MENU BAR").font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundColor(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if pending {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 10)).foregroundStyle(Theme.accent)
                    }
                }
                Text(snap.remainingDisplay)
                    .font(.caption).foregroundStyle(statusColor(snap.status))
                if let weekly = snap.secondaryRemainingPercent,
                   let label = snap.secondaryLabel {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.ringColor(forPercent: weekly)).frame(width: 5, height: 5)
                        Text("\(label) \(Format.percent(weekly))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(Format.relativeTime(snap.fetchedAt))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { state.setMenuBar(config) }
        .help(isMenuBar ? "Shown on the menu bar" : "Click to show on the menu bar")
        .contextMenu {
            Button {
                state.setMenuBar(config)
            } label: { Label("Set as menu bar", systemImage: "checkmark.circle") }
            Button {
                state.togglePendingReminder(config)
            } label: {
                if pending { Label("Reminder queued", systemImage: "bell.badge.fill") }
                else { Label("Remind me on next refresh", systemImage: "bell") }
            }
            Button {
                Task { await state.refreshOne(config) }
            } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
        }
    }

    private func statusColor(_ s: QuotaSnapshot.Status) -> Color {
        switch s {
        case .critical, .invalid, .error: return .red
        case .low: return .orange
        case .ok: return .primary
        default: return .secondary
        }
    }
}
