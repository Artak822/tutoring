import Foundation
import Observation
import TutoringCore

/// Состояние сессии: кто вошёл, к какому серверу подключены, какие справочники загружены.
/// Единственный источник правды для навигации между экраном входа и приложением.
@MainActor
@Observable
final class Session {
    enum State: Equatable {
        /// Проверяем сохранённый токен на старте.
        case launching
        case signedOut
        case signedIn(Tutor)
    }

    private(set) var state: State = .launching
    private(set) var meta: APIMeta?
    private(set) var environment: ServerEnvironment

    let api: TutoringAPI
    private let client: APIClient
    private let defaults: UserDefaults
    private let cache: OfflineCache

    private static let environmentKey = "selected-server-environment"

    init(cache: OfflineCache, defaults: UserDefaults = .standard) {
        self.cache = cache
        self.defaults = defaults

        let stored = defaults.string(forKey: Self.environmentKey)
        let resolved = ServerEnvironment.availableEnvironments
            .first { $0.id == stored } ?? .default
        environment = resolved

        client = APIClient(environment: resolved)
        api = TutoringAPI(client: client)
    }

    var tutor: Tutor? {
        if case .signedIn(let tutor) = state { return tutor }
        return nil
    }

    /// Справочники нужны почти всем экранам, поэтому подписи берём отсюда,
    /// а не хардкодим в интерфейсе.
    func label(forPaymentMethod method: PaymentMethod) -> String {
        meta?.paymentMethods.first { $0.value == method.rawValue }?.label ?? method.rawValue
    }

    func label(forCancellationReason reason: String) -> String {
        meta?.cancellationReasons.first { $0.value == reason }?.label ?? reason
    }

    var currency: String { meta?.currency ?? "₽" }

    // MARK: - Жизненный цикл

    func start() async {
        await client.setUnauthorizedHandler { [weak self] in
            // 401 может прилететь из любого запроса — сессию сбрасываем централизованно.
            await self?.handleUnauthorized()
        }

        guard await client.isAuthenticated else {
            state = .signedOut
            return
        }
        // Токен есть, но он мог быть отозван на сервере — проверяем реальным запросом.
        do {
            try await loadProfile()
        } catch let error as APIError where error.isConnectivity {
            // Связи нет — это не повод выкидывать на экран входа: токен при себе,
            // а экраны умеют жить на кэше. Иначе в метро приложение бесполезно.
            if !restoreProfileFromCache() {
                state = .signedOut
            }
        } catch {
            state = .signedOut
        }
    }

    func signIn(username: String, password: String) async throws {
        _ = try await api.login(username: username, password: password)
        try await loadProfile()
    }

    func register(_ request: RegisterRequest) async throws {
        _ = try await api.register(request)
        try await loadProfile()
    }

    func signOut() async {
        try? await api.logout()
        meta = nil
        state = .signedOut
    }

    func switchEnvironment(to environment: ServerEnvironment) async {
        guard environment != self.environment else { return }
        await client.setEnvironment(environment)
        defaults.set(environment.id, forKey: Self.environmentKey)
        self.environment = environment
        meta = nil
        state = .signedOut
    }

    // MARK: - Внутреннее

    /// Профиль и справочники тянем параллельно — оба нужны до первого экрана.
    private func loadProfile() async throws {
        async let tutor = api.me()
        async let meta = api.meta()
        let (loadedTutor, loadedMeta) = try await (tutor, meta)
        self.meta = loadedMeta
        state = .signedIn(loadedTutor)

        cache.write(loadedTutor, for: CacheKey.profile)
        cache.write(loadedMeta, for: CacheKey.meta)
    }

    /// Вход по последнему известному профилю. Без справочников не пускаем:
    /// без них подписи способов оплаты и причин отмены превратятся в коды.
    private func restoreProfileFromCache() -> Bool {
        guard let tutor = cache.read(Tutor.self, for: CacheKey.profile),
              let meta = cache.read(APIMeta.self, for: CacheKey.meta) else { return false }
        self.meta = meta.value
        state = .signedIn(tutor.value)
        return true
    }

    private func handleUnauthorized() {
        meta = nil
        state = .signedOut
    }
}
