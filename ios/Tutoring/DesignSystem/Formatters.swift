import Foundation
import TutoringCore

/// Форматирование дат. Локаль зафиксирована русской: интерфейс всё равно только на русском,
/// и подписи не должны переключаться на английский из-за языка телефона.
enum DateText {
    static let locale = Locale(identifier: "ru_RU")

    /// Календарь с понедельником как первым днём недели — как в вебе.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }

    private static let dayMonth = formatter("d MMMM")
    /// Год дописываем сами — русский шаблон «d MMMM yyyy» добавляет «г.»,
    /// а в заголовках и подписях эта приписка только удлиняет строку.
    private static let dayMonthYearBase = formatter("d MMMM")
    private static let weekdayShort = formatter("EEEEEE")
    /// Только название месяца: год дописываем сами. Русский шаблон «LLLL yyyy»
    /// добавляет «г.» — в шапке календаря это лишний шум.
    private static let monthOnly = formatter("LLLL")

    /// «25 июля» — для заголовка выбранного дня.
    static func dayMonth(_ date: CalendarDate) -> String {
        dayMonth.string(from: date.date(in: calendar))
    }

    /// «25 июля 2026» — когда год не очевиден.
    static func full(_ date: CalendarDate) -> String {
        dayMonthYearBase.string(from: date.date(in: calendar)) + " \(date.year)"
    }

    /// «Июль 2026» — заголовок месяца.
    static func monthTitle(year: Int, month: Int) -> String {
        let date = CalendarDate(year: year, month: month, day: 1).date(in: calendar)
        return monthOnly.string(from: date).capitalizedFirst + " \(year)"
    }

    /// «Пн», «Вт» — шапка сетки календаря.
    static var weekdaySymbols: [String] {
        // symbols начинаются с воскресенья, а сетка — с понедельника
        let symbols = weekdayShortSymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    private static var weekdayShortSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter.shortWeekdaySymbols.map { $0.capitalizedFirst }
    }

    /// «сегодня» / «завтра» / «пн, 27 июля» — подпись дня в списках.
    static func relativeDay(_ date: CalendarDate) -> String {
        let today = CalendarDate.today(calendar: calendar)
        switch date {
        case today: return "Сегодня"
        case today.adding(days: 1, calendar: calendar): return "Завтра"
        case today.adding(days: -1, calendar: calendar): return "Вчера"
        default:
            return weekdayShort.string(from: date.date(in: calendar)).capitalizedFirst
                + ", " + dayMonth(date)
        }
    }

    /// «5 минут назад», «вчера» — возраст данных из офлайн-кэша.
    /// Форматтер создаём на месте: `RelativeDateTimeFormatter` не Sendable,
    /// а зовут его только когда пропала связь — экономить тут не на чем.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    /// «15:00 – 16:00» — интервал занятия.
    static func timeRange(start: DayTime, durationMinutes: Int) -> String {
        let endMinutes = (start.minutesFromMidnight + durationMinutes) % (24 * 60)
        let end = DayTime(hour: endMinutes / 60, minute: endMinutes % 60)
        return "\(start.serverValue) – \(end.serverValue)"
    }

    /// «1 ч 30 мин» — длительность занятия.
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, let m): return "\(m) мин"
        case (let h, 0): return "\(h) ч"
        case (let h, let m): return "\(h) ч \(m) мин"
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Склонение существительных после числа: «1 занятие», «2 занятия», «5 занятий».
func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod100 = abs(count) % 100
    let mod10 = abs(count) % 10
    if (11...14).contains(mod100) { return "\(count) \(many)" }
    switch mod10 {
    case 1: return "\(count) \(one)"
    case 2...4: return "\(count) \(few)"
    default: return "\(count) \(many)"
    }
}
