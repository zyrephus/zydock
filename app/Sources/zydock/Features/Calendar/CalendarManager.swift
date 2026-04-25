import Foundation
import EventKit
import AppKit
import Combine

@MainActor
final class CalendarManager: ObservableObject {
    enum Authorization {
        case notDetermined
        case denied
        case authorized
    }

    @Published private(set) var authorization: Authorization = .notDetermined
    @Published private(set) var eventsByDay: [Date: [EKEvent]] = [:]

    private let store = EKEventStore()
    private let cal = Calendar.current
    private var changeObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var didStart = false

    private let lookbackDays = 21
    private let lookaheadDays = 21

    init() {
        updateAuthorization()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        refreshTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        Task { await ensureAuthorizedAndRefresh(promptIfNeeded: true) }
    }

    func requestAccess() {
        Task { await ensureAuthorizedAndRefresh(promptIfNeeded: true) }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Queries

    func events(on date: Date) -> [EKEvent] {
        eventsByDay[cal.startOfDay(for: date)] ?? []
    }

    // MARK: - Authorization

    private func updateAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) {
            switch status {
            case .notDetermined: authorization = .notDetermined
            case .denied, .restricted, .writeOnly: authorization = .denied
            case .authorized, .fullAccess: authorization = .authorized
            @unknown default: authorization = .notDetermined
            }
        } else {
            switch status {
            case .notDetermined: authorization = .notDetermined
            case .denied, .restricted: authorization = .denied
            case .authorized: authorization = .authorized
            default: authorization = .notDetermined
            }
        }
    }

    private func ensureAuthorizedAndRefresh(promptIfNeeded: Bool) async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined && promptIfNeeded {
            let granted = await requestSystemAccess()
            authorization = granted ? .authorized : .denied
        } else {
            updateAuthorization()
        }
        if authorization == .authorized {
            refresh()
        }
    }

    private func requestSystemAccess() async -> Bool {
        if #available(macOS 14, *) {
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Refresh

    private func refresh() {
        updateAuthorization()
        guard authorization == .authorized else {
            eventsByDay = [:]
            return
        }

        let today = cal.startOfDay(for: Date())
        guard
            let start = cal.date(byAdding: .day, value: -lookbackDays, to: today),
            let end = cal.date(byAdding: .day, value: lookaheadDays + 1, to: today)
        else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        var grouped: [Date: [EKEvent]] = [:]
        for event in events {
            let day = cal.startOfDay(for: event.startDate)
            grouped[day, default: []].append(event)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.startDate < $1.startDate }
        }
        eventsByDay = grouped
    }
}
