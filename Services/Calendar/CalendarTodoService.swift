import EventKit
import Foundation

enum CalendarTodoError: LocalizedError {
    case permissionDenied
    case noWritableCalendar
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "日历访问未授权，请在系统设置中允许 FlashNote 写入日历。"
        case .noWritableCalendar: "找不到可写入的默认日历，请先在系统日历中设置默认日历。"
        case .emptyTitle: "待办内容不能为空。"
        }
    }
}

@MainActor
final class CalendarTodoService {
    private let eventStore = EKEventStore()

    func add(title: String, start: Date, duration: TimeInterval, notes: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CalendarTodoError.emptyTitle }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            guard try await eventStore.requestWriteOnlyAccessToEvents() else { throw CalendarTodoError.permissionDenied }
        case .writeOnly, .fullAccess, .authorized:
            break
        case .denied, .restricted:
            throw CalendarTodoError.permissionDenied
        @unknown default:
            throw CalendarTodoError.permissionDenied
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else { throw CalendarTodoError.noWritableCalendar }
        let event = EKEvent(eventStore: eventStore)
        event.title = trimmed
        event.startDate = start
        event.endDate = start.addingTimeInterval(max(60, duration))
        event.notes = notes
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent)
    }
}
