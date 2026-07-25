import Foundation
import Observation
import SwiftData

/// Снимок ответа сервера на диске.
///
/// Храним сырой JSON, а не отдельные таблицы под ученика, занятие и группу.
/// Экранам нужен ровно тот формат, что приходит по сети, а модели меняются
/// вместе с API — заводить под них схему SwiftData значит писать миграции ради
/// данных, которые в любой момент перезапрашиваются одним запросом.
@Model
final class CachedResponse {
    @Attribute(.unique) var key: String
    var json: Data
    var updatedAt: Date

    init(key: String, json: Data, updatedAt: Date) {
        self.key = key
        self.json = json
        self.updatedAt = updatedAt
    }
}

/// Что лежало в кэше и насколько оно свежее.
struct CacheSnapshot<Value> {
    let value: Value
    let updatedAt: Date
}

/// Ключи кэша. Собраны в одном месте, чтобы запись и чтение не разъехались.
enum CacheKey {
    static let profile = "profile"
    static let meta = "meta"
    static let dashboard = "dashboard"
    static let groups = "groups"
    static let debts = "debts"

    static func students(isActive: Bool) -> String {
        "students.\(isActive ? "active" : "archived")"
    }

    static func calendarMonth(year: Int, month: Int) -> String {
        String(format: "calendar.%04d-%02d", year, month)
    }

    /// Карточки хранятся поштучно: открытый однажды ученик остаётся доступен
    /// без сети, а те, кого не открывали, места на диске не занимают.
    static func student(_ id: Int) -> String { "student.\(id)" }
    static func studentHistory(_ id: Int) -> String { "studentHistory.\(id)" }
    static func lesson(_ id: Int) -> String { "lesson.\(id)" }
    static func lessonState(_ id: Int) -> String { "lessonState.\(id)" }
}

/// Кэш только на чтение: показать последнее известное состояние, пока идёт запрос,
/// и оставить его на экране, если сети нет. Записи в кэш не создают ничего нового —
/// всё, что пользователь меняет, уходит на сервер напрямую.
@MainActor
@Observable
final class OfflineCache {
    /// Кэш необязателен: если хранилище не поднялось, приложение работает как раньше,
    /// просто без офлайна. Поэтому контекст опциональный, а не падение на старте.
    private let context: ModelContext?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        do {
            let container = try ModelContainer(for: CachedResponse.self)
            context = ModelContext(container)
        } catch {
            context = nil
        }
    }

    func read<Value: Decodable>(_ type: Value.Type, for key: String) -> CacheSnapshot<Value>? {
        guard let context else { return nil }

        var descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1

        guard let row = try? context.fetch(descriptor).first,
              let value = try? decoder.decode(Value.self, from: row.json) else { return nil }
        return CacheSnapshot(value: value, updatedAt: row.updatedAt)
    }

    func write<Value: Encodable>(_ value: Value, for key: String) {
        guard let context, let data = try? encoder.encode(value) else { return }

        var descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1

        if let row = try? context.fetch(descriptor).first {
            row.json = data
            row.updatedAt = .now
        } else {
            context.insert(CachedResponse(key: key, json: data, updatedAt: .now))
        }
        try? context.save()
    }

    /// Выход из аккаунта: снимки прошлого репетитора не должны достаться следующему.
    func clear() {
        guard let context else { return }
        try? context.delete(model: CachedResponse.self)
        try? context.save()
    }
}
