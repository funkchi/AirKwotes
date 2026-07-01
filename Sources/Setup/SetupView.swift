import SwiftUI
import AppKit

struct SetupView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedID: UUID?
    @State private var searchText: String = ""
    @State private var showingAdd: Bool = false
    @State private var editing: ProviderConfig? = nil
    @State private var sidebarTab: SidebarTab = .providers

    enum SidebarTab: String, CaseIterable { case providers = "Providers", relay = "Relay", settings = "Settings" }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(sidebarTab: $sidebarTab)
            Divider()
            HStack(spacing: 0) {
                Sidebar(tab: $sidebarTab, selectedID: $selectedID)
                switch sidebarTab {
                case .providers:
                    HStack(spacing: 0) { listPanel; detailPanel }
                case .relay:
                    RelayPanel()
                case .settings:
                    SettingsPanel()
                }
            }
        }
        .background(Theme.panelBG)
        .frame(minWidth: 1000, minHeight: 640)
        .sheet(isPresented: $showingAdd) {
            AddKeySheet { kind, key, label in
                state.add(kind, apiKey: key, label: label)
            }
        }
        .sheet(item: $editing) { cfg in
            EditKeySheet(config: cfg) { newKey in
                state.updateKey(cfg, apiKey: newKey)
            }
        }
        .onAppear {
            state.completeSetup()
            if selectedID == nil { selectedID = state.menuBarProviderID ?? state.configs.first?.id }
            Task { await state.refreshAll() }
        }
    }

    // MARK: - List panel
    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Providers")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Theme.fieldBG)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).font(.system(size: 13))
                TextField("Search…", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(Theme.fieldBG)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            HStack {
                Text("Menu bar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(state.menuBarConfig?.label ?? "None")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider().padding(.leading, 20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader
                    ForEach(filteredConfigs) { cfg in
                        ProviderListRow(config: cfg,
                                        isSelected: selectedID == cfg.id,
                                        isMenuBar: state.menuBarProviderID == cfg.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = cfg.id }
                            .contextMenu {
                                Button("Set as menu bar") { state.setMenuBar(cfg) }
                                Button {
                                    state.togglePendingReminder(cfg)
                                } label: {
                                    if state.isPendingReminder(cfg) {
                                        Label("Reminder queued", systemImage: "bell.badge.fill")
                                    } else {
                                        Label("Remind me on next refresh", systemImage: "bell")
                                    }
                                }
                                if cfg.kind.requiresAPIKey {
                                    Button("Edit credential…") { editing = cfg }
                                }
                                Divider()
                                Button("Remove", role: .destructive) { state.remove(cfg) }
                            }
                    }
                    if filteredConfigs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray").font(.title2).foregroundStyle(.tertiary)
                            Text("No providers").foregroundStyle(.secondary).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .frame(width: 340)
        .background(.white)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private var sectionHeader: some View {
        Text("Available Providers")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 8)
    }

    private var filteredConfigs: [ProviderConfig] {
        if searchText.isEmpty { return state.configs }
        return state.configs.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.kind.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Detail panel
    @ViewBuilder private var detailPanel: some View {
        if let id = selectedID, let cfg = state.configs.first(where: { $0.id == id }) {
            ProviderDetailPanel(config: cfg) { editing = cfg }
        } else {
            EmptyDetailPanel()
        }
    }
}

private struct ProviderListRow: View {
    let config: ProviderConfig
    let isSelected: Bool
    let isMenuBar: Bool
    @EnvironmentObject var state: AppState

    var body: some View {
        let snap = state.snapshots[config.id] ?? QuotaSnapshot.empty
        HStack(spacing: 10) {
            Ring(remaining: snap.remainingPercent, status: snap.status, size: 26, lineWidth: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(config.label).font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(snap.remainingDisplay).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isMenuBar {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 13))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(isSelected ? Theme.fieldBG : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct EmptyDetailPanel: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Select a provider").font(.headline).foregroundStyle(.secondary)
            Text("Pick a provider on the left to inspect its quota.")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }
}
