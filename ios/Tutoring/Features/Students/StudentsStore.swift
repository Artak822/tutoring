import Foundation
import Observation
import TutoringCore

/// Список учеников. Нужен не только вкладке «Ученики»: без него не собрать
/// форму занятия, поэтому загружается один раз и обновляется после изменений.
@MainActor
@Observable
final class StudentsStore {
    private(set) var students: [Student] = []
    private(set) var archived: [Student] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false
    /// Заполнено, пока на экране данные с диска: сеть ещё не ответила или не ответит.
    private(set) var cachedAt: Date?

    private let api: TutoringAPIProtocol
    private let cache: OfflineCache

    init(api: TutoringAPIProtocol, cache: OfflineCache) {
        self.api = api
        self.cache = cache
    }

    /// Данные с диска, и сеть уже ответила отказом — вот это и есть офлайн.
    /// Пока запрос в пути, плашку не показываем: она мигнула бы на каждом запуске.
    var offlineSince: Date? { errorMessage == nil ? nil : cachedAt }

    func student(_ id: Int) -> Student? {
        students.first { $0.id == id } ?? archived.first { $0.id == id }
    }

    /// Имена для строки занятия: «Петров И., Сидорова А.»
    func names(for ids: [Int]) -> String {
        let names = ids.compactMap { student($0)?.shortName }
        return names.isEmpty ? plural(ids.count, "ученик", "ученика", "учеников") : names.joined(separator: ", ")
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        restoreFromCache()
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await api.students(isActive: true, search: nil, group: nil)
            students = fresh
            cache.write(fresh, for: CacheKey.students(isActive: true))
            cachedAt = nil
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadArchived() async {
        do {
            let fresh = try await api.students(isActive: false, search: nil, group: nil)
            archived = fresh
            cache.write(fresh, for: CacheKey.students(isActive: false))
        } catch {
            // Архив без сети — из кэша: он меняется редко, показать старый лучше, чем пустой
            if archived.isEmpty,
               let snapshot = cache.read([Student].self, for: CacheKey.students(isActive: false)) {
                archived = snapshot.value
            }
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Диск отдаёт данные мгновенно — экран открывается заполненным, а не с прогрессом.
    private func restoreFromCache() {
        guard students.isEmpty,
              let snapshot = cache.read([Student].self, for: CacheKey.students(isActive: true)) else { return }
        students = snapshot.value
        cachedAt = snapshot.updatedAt
    }

    /// Выход из аккаунта: чужие данные не должны мелькнуть под следующим пользователем.
    func reset() {
        students = []
        archived = []
        errorMessage = nil
        hasLoaded = false
        cachedAt = nil
    }

    /// После оплат и отмен балансы учеников меняются на сервере — обновляем список.
    func refreshQuietly() async {
        guard hasLoaded else { return }
        guard let fresh = try? await api.students(isActive: true, search: nil, group: nil) else { return }
        students = fresh
        cache.write(fresh, for: CacheKey.students(isActive: true))
    }
}
