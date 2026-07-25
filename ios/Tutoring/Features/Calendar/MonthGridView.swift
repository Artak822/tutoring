import SwiftUI
import TutoringCore

/// Сетка месяца. Точка под числом означает, что в этот день есть занятия;
/// приглушённая точка — все занятия дня отменены.
struct MonthGridView: View {
    let month: CalendarStore.MonthKey
    let selectedDate: CalendarDate
    let lessonsProvider: (CalendarDate) -> [Lesson]
    let onSelect: (CalendarDate) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private var today: CalendarDate { .today(calendar: DateText.calendar) }

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: 2) {
                ForEach(DateText.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: CalendarDate) -> some View {
        let lessons = lessonsProvider(date)
        let isSelected = date == selectedDate
        let isToday = date == today
        let hasActive = lessons.contains { !$0.isCancelled }

        return Button {
            onSelect(date)
        } label: {
            VStack(spacing: 3) {
                Text("\(date.day)")
                    .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday))
                Circle()
                    .frame(width: 5, height: 5)
                    .foregroundStyle(dotColor(isSelected: isSelected, hasActive: hasActive))
                    .opacity(lessons.isEmpty ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    // Выбранный день — единственное место сетки с градиентом:
                    // он и должен быть заметен издалека.
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.brandGradient)
                        .shadow(color: Palette.violetDeep.opacity(0.35), radius: 8, x: 0, y: 4)
                } else if isToday {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.brandSurface)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(
            "\(DateText.full(date)), \(plural(lessons.count, "занятие", "занятия", "занятий"))"
        )
    }

    private func dayColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return Palette.brand }
        return .primary
    }

    private func dotColor(isSelected: Bool, hasActive: Bool) -> Color {
        if isSelected { return .white }
        return hasActive ? Palette.brand : Palette.muted
    }

    /// nil — пустая клетка до первого числа месяца.
    private var gridDays: [CalendarDate?] {
        let calendar = DateText.calendar
        let first = CalendarDate(year: month.year, month: month.month, day: 1)
        let daysInMonth = first.endOfMonth(calendar: calendar).day

        // Смещение до понедельника: weekday у Calendar начинается с воскресенья
        let weekday = calendar.component(.weekday, from: first.date(in: calendar))
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        return Array(repeating: nil, count: leading)
            + (1...daysInMonth).map { CalendarDate(year: month.year, month: month.month, day: $0) }
    }
}
