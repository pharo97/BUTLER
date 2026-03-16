import EventKit
import Foundation

// MARK: - CalendarBridge

/// Fetches upcoming calendar events via EventKit.
///
/// Permission: `NSCalendarsFullAccessUsageDescription` (macOS 14+).
/// Silently returns empty strings if permission denied — BUTLER degrades gracefully.
@MainActor
final class CalendarBridge {

    private let store = EKEventStore()
    private(set) var isAuthorized: Bool = false

    // MARK: - Permission

    func requestAccessIfNeeded() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            isAuthorized = true
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                isAuthorized = granted
            } catch {
                isAuthorized = false
            }
        default:
            isAuthorized = false
        }
    }

    // MARK: - Query

    /// Returns a human-readable summary of the next event starting within `minutes`.
    /// Returns empty string if no event found or permission denied.
    func nextEventSummary(withinMinutes minutes: Int = 20) -> String {
        guard isAuthorized else { return "" }

        let now   = Date()
        let limit = Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now

        let pred = store.predicateForEvents(withStart: now, end: limit, calendars: nil)
        let events = store.events(matching: pred)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        guard let next = events.first else { return "" }

        let minutesUntil = Int(next.startDate.timeIntervalSince(now) / 60)
        let timeLabel = minutesUntil <= 1 ? "now" : "in \(minutesUntil) minutes"
        return "\(next.title ?? "Meeting") \(timeLabel)"
    }
}
