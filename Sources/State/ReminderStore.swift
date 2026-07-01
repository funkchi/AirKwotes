import EventKit
import Foundation

/// Thin wrapper around EventKit for creating macOS Reminders.
enum ReminderStore {
    private static let store = EKEventStore()

    @discardableResult
    static func requestAccess() async -> Bool {
        if #available(macOS 14, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        }
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .reminder) { granted, _ in cont.resume(returning: granted) }
        }
    }

    static func createReminder(title: String, notes: String?) async {
        guard await requestAccess() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try? store.save(reminder, commit: true)
    }
}
