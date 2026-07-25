import Foundation
import Observation
import TutoringCore

/// Занятия по месяцам. Календарь листают вперёд-назад постоянно, поэтому загруженные
/// месяцы держим в памяти и не перезапрашиваем при каждом свайпе.
@MainActor
@Observable
final class CalendarStore {
    struct MonthKey: Hashable {
        let year: Int
        let month: Int

        static func current(calendar: Calendar = DateText.calendar) -> MonthKey {
            let today = CalendarDate.today(calendar: calendar)
            return MonthKey(year: today.year, month: today.month)
        }

        func advanced(by months: Int, calendar: Calendar = DateText.calendar) -> MonthKey {
            let base = CalendarDate(year: year, month: month, day: 1).date(in: calendar)
            let shifted = calendar.date(byAdding: .month, value: months, to: base) ?? base
            let date = CalendarDate(date: shifted, calendar: calendar)
            return MonthKey(year: date.year, month: date.month)
        }
    }

    private(set) var lessonsByDate: [CalendarDate: [Lesson]] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var visibleMonth: MonthKey = .current()
    var selectedDate: CalendarDate = .today(calendar: DateText.calendar)

    private var loadedMonths: Set<MonthKey> = []
    /// Месяцы, поднятые с диска: с них снимаем метку, как только ответит сервер.
    private var cachedMonths: [MonthKey: Date] = [:]

    private let api: TutoringAPIProtocol
    private let cache: OfflineCache

    init(api: TutoringAPIProtocol, cache: OfflineCache) {
        self.api = api
        self.cache = cache
    }

    /// Заполнено, пока видимый месяц показан с диска.
    var cachedAt: Date? { cachedMonths[visibleMonth] }

    /// Данные с диска, и сеть уже ответила отказом — вот это и есть офлайн.
    var offlineSince: Date? { errorMessage == nil ? nil : cachedAt }

    func lessons(on date: CalendarDate) -> [Lesson] {
        lessonsByDate[date] ?? []
    }

    var selectedDayLessons: [Lesson] {
        lessons(on: selectedDate)
    }

    /// Всё загруженное разом — напоминаниям и виджету нужен плоский список,
    /// а не разбивка по дням.
    var allLessons: [Lesson] {
        lessonsByDate.values.flatMap { $0 }
    }

    /// Занятия ближайших дней — для вкладки «Сегодня» и виджета.
    func upcoming(from date: CalendarDate, days: Int) -> [(CalendarDate, [Lesson])] {
        (0..<days)
            .map { date.adding(days: $0, calendar: DateText.calendar) }
            .compactMap { day in
                let lessons = lessons(on: day)
                return lessons.isEmpty ? nil : (day, lessons)
            }
    }

    // MARK: - Загрузка

    func loadIfNeeded(_ key: MonthKey) async {
        guard !loadedMonths.contains(key) else { return }
        restoreFromCache(key)
        await load(key)
    }

    func load(_ key: MonthKey) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let month = try await api.calendarMonth(year: key.year, month: key.month)
            apply(month)
            loadedMonths.insert(key)
            cachedMonths[key] = nil
            cache.write(month, for: CacheKey.calendarMonth(year: key.year, month: key.month))
            errorMessage = nil
        } catch is CancellationError {
            // Пользователь ушёл с экрана — молча выходим
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Перезагружает видимый месяц — после любых изменений занятий.
    func reloadVisibleMonth() async {
        loadedMonths.remove(visibleMonth)
        await load(visibleMonth)
    }

    /// Занятие могло переехать в другой месяц: чистим кэш целиком,
    /// иначе оно останется на старой дате до перезапуска.
    func invalidateAll() {
        loadedMonths.removeAll()
        cachedMonths.removeAll()
        lessonsByDate.removeAll()
    }

    /// Занятия месяца с диска — календарь открывается сразу заполненным.
    /// Месяц не помечаем загруженным: сеть всё равно должна сказать своё слово.
    private func restoreFromCache(_ key: MonthKey) {
        guard let snapshot = cache.read(
            CalendarMonth.self, for: CacheKey.calendarMonth(year: key.year, month: key.month)
        ) else { return }
        apply(snapshot.value)
        cachedMonths[key] = snapshot.updatedAt
    }

    /// Выход из аккаунта: чужие занятия не должны мелькнуть под следующим пользователем.
    func reset() {
        invalidateAll()
        errorMessage = nil
        visibleMonth = .current()
        selectedDate = .today(calendar: DateText.calendar)
    }

    private func apply(_ month: CalendarMonth) {
        let key = MonthKey(year: month.year, month: month.month)

        // Сначала убираем старые занятия этого месяца, иначе удалённые останутся на экране
        for date in lessonsByDate.keys where date.year == key.year && date.month == key.month {
            lessonsByDate[date] = nil
        }

        for lesson in month.lessons {
            lessonsByDate[lesson.date, default: []].append(lesson)
        }
        for date in lessonsByDate.keys where date.year == key.year && date.month == key.month {
            lessonsByDate[date]?.sort { $0.time < $1.time }
        }
    }
}
