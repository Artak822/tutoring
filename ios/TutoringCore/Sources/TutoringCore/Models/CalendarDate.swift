import Foundation

/// Календарная дата без времени и часового пояса — то, что сервер шлёт как «2026-07-25».
///
/// Обычный `Date` тут вреден: занятие 25 июля должно остаться 25 июля независимо от того,
/// в каком поясе находится телефон. Поэтому храним компоненты, а в `Date` превращаем
/// только для отображения.
public struct CalendarDate: Hashable, Sendable, Comparable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Дата в текущем календаре пользователя — например, «сегодня» для подсветки в календаре.
    public init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }

    public static func today(calendar: Calendar = .current) -> CalendarDate {
        CalendarDate(date: Date(), calendar: calendar)
    }

    public var serverValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Полдень, а не полночь: полночь в некоторых поясах при переходе на летнее время
    /// не существует, и `Calendar` возвращает соседний день.
    public func date(in calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDate {
        let shifted = calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? Date()
        return CalendarDate(date: shifted, calendar: calendar)
    }

    public var startOfMonth: CalendarDate {
        CalendarDate(year: year, month: month, day: 1)
    }

    public func endOfMonth(calendar: Calendar = .current) -> CalendarDate {
        let range = calendar.range(of: .day, in: .month, for: startOfMonth.date(in: calendar))
        return CalendarDate(year: year, month: month, day: range?.count ?? 28)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = CalendarDate(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Не удалось разобрать дату: \(raw)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serverValue)
    }
}

/// Время начала занятия — «15:00:00» с сервера. Секунды сервер шлёт, но нам они не нужны.
public struct DayTime: Hashable, Sendable, Comparable, Codable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }

    public var serverValue: String { String(format: "%02d:%02d", hour, minute) }
    public var displayValue: String { serverValue }

    public var minutesFromMidnight: Int { hour * 60 + minute }

    public static func < (lhs: DayTime, rhs: DayTime) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = DayTime(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Не удалось разобрать время: \(raw)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serverValue)
    }
}

extension CalendarDate {
    /// Момент начала занятия — нужен для сортировки и локальных напоминаний.
    public func combined(with time: DayTime, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? date(in: calendar)
    }
}
