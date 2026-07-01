import Foundation
import SwiftUI
import ServiceManagement
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    @Published var configs: [ProviderConfig] = []
    @Published var snapshots: [UUID: QuotaSnapshot] = [:]
    @Published var menuBarProviderID: UUID?
    @Published var monitoringEnabled: Bool = true
    @Published var isRefreshing: Bool = false
    @Published var didCompleteSetup: Bool = false
    @Published var lastError: String?

    // Settings
    @Published var pollingIntervalMinutes: Int = 5
    @Published var launchAtLogin: Bool = false
    @Published var notificationsEnabled: Bool = true
    @Published var lowThreshold: Double = 0.20
    @Published var menuBarShowsPercent: Bool = true
    @Published var menuBarShowsLabel: Bool = false

    // Providers whose next refresh should produce a macOS Reminder.
    @Published var pendingReminders: Set<UUID> = []

    private let defaults = UserDefaults.standard
    private let registry = Providers.registry()
    private var timer: Timer?
    private var lowWarned: Set<UUID> = []
    private var failureCounts: [UUID: Int] = [:]
    private var lastGoodSnapshots: [UUID: QuotaSnapshot] = [:]

    /// Consecutive transient failures required before surfacing a "sync failed" state.
    static let failureThreshold = 3

    enum Keys {
        static let configs = "ak.configs.v1"; static let menu = "ak.menubar.v1"
        static let enabled = "ak.enabled.v1"; static let setup = "ak.setup.v1"
        static let pollMin = "ak.pollMin.v1"; static let login = "ak.login.v1"
        static let notif = "ak.notif.v1"; static let threshold = "ak.threshold.v1"
        static let mbPercent = "ak.mbPercent.v1"; static let mbLabel = "ak.mbLabel.v1"
    }

    static let pollingOptions: [Int] = [1, 5, 15, 30, 60]

    init() {
        load()
        if configs.isEmpty { didCompleteSetup = false }
        NotificationCenter.default.addObserver(
            forName: .refreshRequested, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    // MARK: - Persistence
    private func load() {
        if let data = defaults.data(forKey: Keys.configs),
           let saved = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            configs = saved
        }
        if let id = defaults.string(forKey: Keys.menu), let uid = UUID(uuidString: id) {
            menuBarProviderID = configs.first(where: { $0.id == uid })?.id
        }
        if menuBarProviderID == nil { menuBarProviderID = configs.first?.id }
        monitoringEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        didCompleteSetup = defaults.bool(forKey: Keys.setup) || !configs.isEmpty
        pollingIntervalMinutes = (defaults.object(forKey: Keys.pollMin) as? Int) ?? 5
        launchAtLogin = defaults.bool(forKey: Keys.login)
        notificationsEnabled = (defaults.object(forKey: Keys.notif) as? Bool) ?? true
        lowThreshold = (defaults.object(forKey: Keys.threshold) as? Double) ?? 0.20
        menuBarShowsPercent = (defaults.object(forKey: Keys.mbPercent) as? Bool) ?? true
        menuBarShowsLabel = defaults.bool(forKey: Keys.mbLabel)
        if launchAtLogin { try? SMAppService.mainApp.register() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: Keys.configs)
        }
        defaults.set(menuBarProviderID?.uuidString, forKey: Keys.menu)
        defaults.set(monitoringEnabled, forKey: Keys.enabled)
        defaults.set(didCompleteSetup, forKey: Keys.setup)
        defaults.set(pollingIntervalMinutes, forKey: Keys.pollMin)
        defaults.set(launchAtLogin, forKey: Keys.login)
        defaults.set(notificationsEnabled, forKey: Keys.notif)
        defaults.set(lowThreshold, forKey: Keys.threshold)
        defaults.set(menuBarShowsPercent, forKey: Keys.mbPercent)
        defaults.set(menuBarShowsLabel, forKey: Keys.mbLabel)
    }

    // MARK: - Provider management
    func add(_ kind: ProviderKind, apiKey: String, label: String? = nil) {
        let cfg = ProviderConfig(kind: kind, label: label)
        configs.append(cfg)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            KeychainStore.setAPIKey(trimmedKey, for: cfg.id.uuidString)
        }
        if menuBarProviderID == nil { menuBarProviderID = cfg.id }
        persist()
        Task { await refreshOne(cfg) }
    }

    func updateKey(_ cfg: ProviderConfig, apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            KeychainStore.deleteAPIKey(for: cfg.id.uuidString)
        } else {
            KeychainStore.setAPIKey(trimmedKey, for: cfg.id.uuidString)
        }
        Task { await refreshOne(cfg) }
    }

    func remove(_ cfg: ProviderConfig) {
        KeychainStore.deleteAPIKey(for: cfg.id.uuidString)
        configs.removeAll { $0.id == cfg.id }
        snapshots.removeValue(forKey: cfg.id)
        lastGoodSnapshots.removeValue(forKey: cfg.id)
        failureCounts.removeValue(forKey: cfg.id)
        pendingReminders.remove(cfg.id)
        lowWarned.remove(cfg.id)
        if menuBarProviderID == cfg.id { menuBarProviderID = configs.first?.id }
        persist()
    }

    func keyExists(for cfg: ProviderConfig) -> Bool {
        KeychainStore.getAPIKey(for: cfg.id.uuidString) != nil
    }

    func maskedKey(for cfg: ProviderConfig) -> String {
        guard let k = KeychainStore.getAPIKey(for: cfg.id.uuidString) else { return "Not set" }
        return Format.masked(k)
    }

    func setMenuBar(_ cfg: ProviderConfig) {
        menuBarProviderID = cfg.id
        persist()
    }

    func toggleMonitoring(_ on: Bool) {
        monitoringEnabled = on
        persist()
        if on { startTimer() } else { stopTimer() }
    }

    func completeSetup() {
        didCompleteSetup = true
        persist()
    }

    // MARK: - Settings actions
    func setPollingInterval(_ minutes: Int) {
        pollingIntervalMinutes = minutes
        persist()
        startTimer()
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
        persist()
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
    }

    func setNotifications(_ on: Bool) {
        notificationsEnabled = on
        persist()
        if on {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func setLowThreshold(_ value: Double) {
        lowThreshold = min(0.9, max(0.05, value))
        lowWarned.removeAll()
        persist()
    }

    func setMenuBarShowsPercent(_ on: Bool) { menuBarShowsPercent = on; persist() }
    func setMenuBarShowsLabel(_ on: Bool) { menuBarShowsLabel = on; persist() }

    func resetAllData() {
        for cfg in configs { KeychainStore.deleteAPIKey(for: cfg.id.uuidString) }
        configs.removeAll()
        snapshots.removeAll()
        lowWarned.removeAll()
        failureCounts.removeAll()
        lastGoodSnapshots.removeAll()
        pendingReminders.removeAll()
        menuBarProviderID = nil
        didCompleteSetup = false
        persist()
    }

    // MARK: - Reminders
    func togglePendingReminder(_ cfg: ProviderConfig) {
        if pendingReminders.contains(cfg.id) {
            pendingReminders.remove(cfg.id)
        } else {
            pendingReminders.insert(cfg.id)
            Task { _ = await ReminderStore.requestAccess() }
        }
    }

    func isPendingReminder(_ cfg: ProviderConfig) -> Bool {
        pendingReminders.contains(cfg.id)
    }

    private func makeReminder(for cfg: ProviderConfig, snap: QuotaSnapshot) async {
        var body = snap.remainingDisplay
        if let p = snap.remainingPercent { body += " · \(Format.percent(p)) remaining" }
        if let sec = snap.secondaryRemainingPercent, let label = snap.secondaryLabel {
            body += " · \(label) \(Format.percent(sec)) remaining"
        }
        if let reset = snap.resetAt { body += " · resets \(Format.relativeTime(reset))" }
        if case .error(let m) = snap.status { body = "Sync failed: \(m)" }
        await ReminderStore.createReminder(title: "AirKwotes — \(cfg.label)", notes: body)
    }

    // MARK: - Refresh
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (UUID, QuotaSnapshot?).self) { group in
            for cfg in configs where cfg.enabled {
                group.addTask { [weak self] in
                    guard let self else { return (UUID(), nil) }
                    let snap = await self.fetch(cfg)
                    return (cfg.id, snap)
                }
            }
            for await (id, snap) in group {
                if let snap, let cfg = self.configs.first(where: { $0.id == id }) {
                    self.record(cfg, result: snap)
                }
            }
        }
        startTimer()
    }

    func refreshOne(_ cfg: ProviderConfig) async {
        let snap = await fetch(cfg)
        record(cfg, result: snap)
    }

    /// Stores a refresh result, suppressing transient failures until they repeat
    /// `failureThreshold` times consecutively. Also fulfills pending reminders.
    private func record(_ cfg: ProviderConfig, result: QuotaSnapshot) {
        let stored: QuotaSnapshot
        if result.status.isTransientFailure {
            failureCounts[cfg.id, default: 0] += 1
            if failureCounts[cfg.id, default: 0] >= Self.failureThreshold {
                stored = result
            } else if let good = lastGoodSnapshots[cfg.id] {
                stored = good           // keep showing the last good snapshot
            } else {
                stored = result
            }
        } else {
            failureCounts[cfg.id] = 0
            lastGoodSnapshots[cfg.id] = result
            stored = result
        }
        snapshots[cfg.id] = stored
        checkWarning(id: cfg.id, snap: stored)

        if pendingReminders.contains(cfg.id) {
            pendingReminders.remove(cfg.id)
            let snap = stored
            Task { await makeReminder(for: cfg, snap: snap) }
        }
    }

    private func fetch(_ cfg: ProviderConfig) async -> QuotaSnapshot {
        guard let provider = registry[cfg.kind] else { return fail(.unsupported) }
        let key = provider.requiresAPIKey ? (KeychainStore.getAPIKey(for: cfg.id.uuidString) ?? "") : ""
        guard !provider.requiresAPIKey || !key.isEmpty else { return fail(.invalid) }
        do {
            return try await provider.fetch(apiKey: key)
        } catch {
            var s = QuotaSnapshot.empty
            s.status = .error(error.localizedDescription)
            s.fetchedAt = Date()
            return s
        }
    }

    private func fail(_ s: QuotaSnapshot.Status) -> QuotaSnapshot {
        var v = QuotaSnapshot.empty; v.status = s; v.fetchedAt = Date(); return v
    }

    // MARK: - Polling
    func startTimer() {
        stopTimer()
        guard monitoringEnabled else { return }
        let interval = TimeInterval(max(1, pollingIntervalMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }
    func stopTimer() { timer?.invalidate(); timer = nil }

    // MARK: - Derived
    var menuBarSnapshot: QuotaSnapshot {
        guard let id = menuBarProviderID else { return QuotaSnapshot.empty }
        return snapshots[id] ?? QuotaSnapshot.empty
    }
    var menuBarConfig: ProviderConfig? { configs.first(where: { $0.id == menuBarProviderID }) }

    var problems: [ProviderConfig] {
        configs.filter { c in (snapshots[c.id]?.status.isProblem ?? false) }
    }

    var lowOrCritical: [ProviderConfig] {
        configs.filter { c in
            guard let s = snapshots[c.id] else { return false }
            return s.status == .low || s.status == .critical
        }
    }

    private func checkWarning(id: UUID, snap: QuotaSnapshot) {
        let isLow: Bool = {
            if case .critical = snap.status { return true }
            return snap.remainingPercent.map { $0 < lowThreshold } ?? false
        }()
        if isLow && !lowWarned.contains(id) {
            lowWarned.insert(id)
            NotificationCenter.default.post(name: .quotaLowWarning, object: snap)
            if notificationsEnabled, let cfg = configs.first(where: { $0.id == id }) {
                postLowNotification(snap, label: cfg.label)
            }
        } else if !isLow {
            lowWarned.remove(id)
        }
    }

    private func postLowNotification(_ snap: QuotaSnapshot, label: String) {
        let content = UNMutableNotificationContent()
        content.title = "Low quota — \(label)"
        content.body = "\(snap.remainingDisplay) remaining"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

extension Notification.Name {
    static let quotaLowWarning = Notification.Name("ak.quotaLowWarning")
    static let refreshRequested = Notification.Name("ak.refreshRequested")
}
