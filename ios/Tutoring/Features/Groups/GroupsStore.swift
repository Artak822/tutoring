import Foundation
import Observation
import TutoringCore

/// Список групп. Нужен и вкладке «Ещё», и форме ученика (выбор групп),
/// поэтому живёт отдельно от экрана.
@MainActor
@Observable
final class GroupsStore {
    private(set) var groups: [StudentGroup] = []
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
    var offlineSince: Date? { errorMessage == nil ? nil : cachedAt }

    func group(_ id: Int) -> StudentGroup? {
        groups.first { $0.id == id }
    }

    /// Подпись «11 класс, Олимпиадники» под именем ученика в карточке.
    func names(for ids: [Int]) -> String {
        ids.compactMap { group($0)?.name }.joined(separator: ", ")
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
            let fresh = try await api.groups()
            groups = fresh
            cache.write(fresh, for: CacheKey.groups)
            cachedAt = nil
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func restoreFromCache() {
        guard groups.isEmpty,
              let snapshot = cache.read([StudentGroup].self, for: CacheKey.groups) else { return }
        groups = snapshot.value
        cachedAt = snapshot.updatedAt
    }

    func reset() {
        groups = []
        errorMessage = nil
        hasLoaded = false
        cachedAt = nil
    }
}
