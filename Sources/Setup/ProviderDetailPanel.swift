import SwiftUI

struct ProviderDetailPanel: View {
    let config: ProviderConfig
    let onEditKey: () -> Void
    @EnvironmentObject var state: AppState

    var body: some View {
        let snap = state.snapshots[config.id] ?? QuotaSnapshot.empty
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topSection(snap)
                statsGrid(snap)
                metaSection(snap)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }

    @ViewBuilder
    private func topSection(_ snap: QuotaSnapshot) -> some View {
        HStack(alignment: .center, spacing: 28) {
            Ring(remaining: snap.remainingPercent, status: snap.status,
                 size: 132, lineWidth: 12, label: nil)
            VStack(alignment: .leading, spacing: 6) {
                Text(config.label).font(.system(size: 26, weight: .bold))
                Text(config.kind.displayName)
                    .font(.title3).foregroundStyle(.secondary)
                Text(config.kind.summary)
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .padding(.top, 2)
                HStack(spacing: 10) {
                    if config.kind.requiresAPIKey {
                        Button("Edit credential…", action: onEditKey).buttonStyle(.bordered)
                    }
                    if state.menuBarProviderID != config.id {
                        Button("Set as menu bar") { state.setMenuBar(config) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Label("Shown in menu bar", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Button {
                        state.togglePendingReminder(config)
                    } label: {
                        if state.isPendingReminder(config) {
                            Label("Reminder queued", systemImage: "bell.badge.fill")
                        } else {
                            Label("Remind me on next refresh", systemImage: "bell")
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }.padding(.top, 8)
            }
        }
    }

    private func statsGrid(_ snap: QuotaSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("Remaining", value: snap.remainingDisplay,
                     color: Theme.ringColor(forPercent: snap.remainingPercent ?? 1))
            statCard("Used", value: snap.usedDisplay ?? "—")
            statCard("Total", value: snap.totalDisplay ?? "—")
            statCard("Last sync", value: Format.relativeTime(snap.fetchedAt))
            if let weekly = snap.secondaryRemainingPercent, let label = snap.secondaryLabel {
                statCard(label, value: "\(Format.percent(weekly)) remaining",
                         color: Theme.ringColor(forPercent: weekly))
            }
        }
    }

    private func statCard(_ title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.fieldBG, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func metaSection(_ snap: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if config.kind.requiresAPIKey {
                row("Credential", value: state.maskedKey(for: config))
            } else {
                row("Source", value: "~/.codex local logs")
            }
            row("Provider ID", value: config.id.uuidString.prefix(8) + "…")
            if let reset = snap.resetAt {
                row("Resets", value: Format.relativeTime(reset))
            }
            if let note = snap.note {
                row("Note", value: note)
            }
            if case .error(let m) = snap.status {
                row("Error", value: m)
            }
        }
    }

    private func row(_ k: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.subheadline).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
