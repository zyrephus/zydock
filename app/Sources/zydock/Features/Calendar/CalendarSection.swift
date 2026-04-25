import SwiftUI
import AppKit
import EventKit

struct CalendarSection: View {
    @ObservedObject var calendar: CalendarManager
    var isExpanded: Bool

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var dragOffset: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var scrollEndWork: DispatchWorkItem?

    private let cellWidth: CGFloat = 34
    private let dayRange: ClosedRange<Int> = -21...21
    private let cal = Calendar.current

    private var today: Date { cal.startOfDay(for: Date()) }

    private var currentOffset: CGFloat {
        let days = cal.dateComponents([.day], from: today, to: selectedDate).day ?? 0
        return CGFloat(days) * cellWidth
    }

    var body: some View {
        VStack(spacing: 6) {
            monthHeader
            carousel
                .frame(height: 50)
            eventRows
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { resetToToday(animated: false) }
        .onChange(of: isExpanded) { expanded in
            if !expanded { resetToToday(animated: false) }
        }
    }

    private func resetToToday(animated: Bool) {
        let action = { selectedDate = today; dragOffset = 0 }
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { action() }
        } else {
            action()
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        Text(monthString(for: selectedDate))
            .font(.system(size: Typography.secondary, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .animation(.easeInOut(duration: 0.18), value: monthString(for: selectedDate))
    }

    private func openCalendarApp(on date: Date) {
        guard calendar.authorization == .authorized else { return }
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return }
        let source = """
        set targetDate to current date
        set year of targetDate to \(year)
        set month of targetDate to \(month)
        set day of targetDate to \(day)
        set time of targetDate to 0
        tell application "Calendar"
            activate
            view calendar at targetDate
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    private func monthString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date).uppercased()
    }

    // MARK: - Carousel

    private var carousel: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            ZStack {
                ForEach(dayRange, id: \.self) { offset in
                    let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
                    let position = CGFloat(offset) * cellWidth - currentOffset + dragOffset
                    let distance = abs(position) / cellWidth
                    let scale = max(0.55, 1.0 - distance * 0.18)
                    let isCenter = distance < 0.5

                    Button {
                        if isCenter {
                            openCalendarApp(on: selectedDate)
                        } else {
                            jump(to: date)
                        }
                    } label: {
                        dayCell(date: date, isCenter: isCenter)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(scale)
                    .position(x: center + position, y: geo.size.height / 2)
                }
            }
            .mask(fadeMask(width: geo.size.width))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    enableScrollMonitor()
                case .ended:
                    disableScrollMonitor()
                }
            }
            .onDisappear { disableScrollMonitor() }
        }
    }

    // MARK: - Scroll wheel

    private func enableScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleScroll(event)
            return nil
        }
    }

    private func disableScrollMonitor() {
        if let m = scrollMonitor {
            NSEvent.removeMonitor(m)
            scrollMonitor = nil
        }
        scrollEndWork?.cancel()
        scrollEndWork = nil
    }

    private func handleScroll(_ event: NSEvent) {
        let dx: CGFloat = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        dragOffset += dx

        scrollEndWork?.cancel()
        if event.phase == .ended || event.momentumPhase == .ended {
            snap(toProjectedTranslation: dragOffset)
            return
        }
        let work = DispatchWorkItem { snap(toProjectedTranslation: dragOffset) }
        scrollEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Snap

    private func snap(toProjectedTranslation translation: CGFloat) {
        let projected = currentOffset - translation
        let snappedDays = Int((projected / cellWidth).rounded())
        let clamped = max(dayRange.lowerBound, min(dayRange.upperBound, snappedDays))
        let newDate = cal.date(byAdding: .day, value: clamped, to: today) ?? today
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            selectedDate = newDate
            dragOffset = 0
        }
    }

    private func jump(to date: Date) {
        let day = cal.startOfDay(for: date)
        guard !cal.isDate(day, inSameDayAs: selectedDate) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            selectedDate = day
            dragOffset = 0
        }
    }

    private func dayCell(date: Date, isCenter: Bool) -> some View {
        let isToday = cal.isDate(date, inSameDayAs: today)
        return VStack(spacing: 1) {
            Text(weekdayString(for: date))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(isCenter ? 0.6 : 0.4))
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 22, weight: isCenter ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isCenter ? 1.0 : 0.7))
                .monospacedDigit()
            Circle()
                .fill(.white.opacity(0.75))
                .frame(width: 3, height: 3)
                .opacity(isToday ? 1 : 0)
        }
        .frame(width: cellWidth)
        .contentShape(Rectangle())
    }

    private func weekdayString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func fadeMask(width: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.30),
                .init(color: .white, location: 0.70),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width)
    }

    // MARK: - Event rows

    @ViewBuilder
    private var eventRows: some View {
        switch calendar.authorization {
        case .notDetermined:
            grantAccessView
        case .denied:
            deniedView
        case .authorized:
            authorizedRows
        }
    }

    private var grantAccessView: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Button(action: { calendar.requestAccess() }) {
                Text("Grant Calendar access")
                    .font(.system(size: Typography.secondary, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(NotchPressStyle())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var deniedView: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            Text("Calendar access denied")
                .font(.system(size: Typography.secondary))
                .foregroundStyle(.white.opacity(0.45))
            Button(action: { calendar.openSystemSettings() }) {
                Text("Open Settings")
                    .font(.system(size: Typography.secondary, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .underline()
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var authorizedRows: some View {
        let events = Array(calendar.events(on: selectedDate).prefix(3))
        if events.isEmpty {
            VStack {
                Spacer(minLength: 0)
                Text("No events")
                    .font(.system(size: Typography.secondary))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 4) {
                ForEach(events, id: \.eventIdentifier) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        Button(action: { openCalendarApp(on: selectedDate) }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.calendar?.color ?? .systemGray))
                    .frame(width: 3, height: 14)
                Text(timeText(for: event))
                    .font(.system(size: Typography.secondary))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 48, alignment: .leading)
                Text(event.title ?? "")
                    .font(.system(size: Typography.secondary))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressStyle())
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private func timeText(for event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        return Self.timeFormatter.string(from: event.startDate)
    }
}
