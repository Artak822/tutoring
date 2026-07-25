import Foundation
import os

/// Клиент REST API. Один на приложение, живёт в акторе: токен и текущий сервер
/// читаются из нескольких задач одновременно.
public actor APIClient {
    public private(set) var environment: ServerEnvironment
    private let tokenStore: any TokenStoring
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "app.tutoring", category: "api")

    /// Срабатывает, когда сервер ответил 401: интерфейс должен показать экран входа.
    private var unauthorizedHandler: (@Sendable () async -> Void)?

    public init(
        environment: ServerEnvironment = .default,
        tokenStore: any TokenStoring = KeychainTokenStore(),
        session: URLSession? = nil
    ) {
        self.environment = environment
        self.tokenStore = tokenStore

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Состояние

    public var isAuthenticated: Bool {
        tokenStore.read() != nil
    }

    public func setEnvironment(_ environment: ServerEnvironment) {
        // Токен привязан к серверу, поэтому при смене стенда сессия сбрасывается.
        guard environment != self.environment else { return }
        self.environment = environment
        tokenStore.clear()
    }

    public func setUnauthorizedHandler(_ handler: @escaping @Sendable () async -> Void) {
        unauthorizedHandler = handler
    }

    public func storeToken(_ token: String) {
        tokenStore.write(token)
    }

    public func clearToken() {
        tokenStore.clear()
    }

    // MARK: - Запросы

    @discardableResult
    public func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint, as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await perform(endpoint)
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            logger.error("Не удалось разобрать \(endpoint.path): \(error.localizedDescription)")
            throw APIError.decoding("\(endpoint.path): \(error)")
        }
    }

    /// Для запросов без тела ответа — DELETE, logout, archive.
    public func sendIgnoringResponse(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        let request = try makeRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            // Недоступный хост здесь — то же самое, что пропавшая сеть: данных нет,
            // но и повода считать сессию протухшей тоже нет.
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw APIError.offline
            case .timedOut:
                throw APIError.timeout
            case .cancelled:
                throw CancellationError()
            default:
                throw APIError.transport(error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Некорректный ответ сервера")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            tokenStore.clear()
            if let unauthorizedHandler {
                await unauthorizedHandler()
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden(Self.message(from: data, decoder: decoder) ?? "")
        case 404:
            // Чужие записи сервер тоже отдаёт как 404 — это ожидаемо, не баг.
            throw APIError.notFound
        case 400, 409, 422:
            throw APIError.validation(Self.fieldErrors(from: data))
        default:
            logger.error("HTTP \(http.statusCode) на \(endpoint.path)")
            throw APIError.server(
                status: http.statusCode,
                message: Self.message(from: data, decoder: decoder)
            )
        }
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(
            url: environment.apiRoot.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.query.isEmpty {
            components?.queryItems = endpoint.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw APIError.transport("Некорректный адрес запроса")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if endpoint.requiresAuth, let token = tokenStore.read() {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.decoding("Не удалось собрать тело запроса: \(error)")
            }
        }

        return request
    }

    // MARK: - Разбор ошибок

    /// DRF отдаёт `{"detail": "..."}`, services.py — `{"error": "..."}`.
    private static func message(from data: Data, decoder: JSONDecoder) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object["detail"] as? String) ?? (object["error"] as? String)
    }

    private static func fieldErrors(from data: Data) -> [String: [String]] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["non_field_errors": ["Не удалось выполнить запрос"]]
        }

        var result: [String: [String]] = [:]
        for (key, value) in object {
            switch value {
            case let strings as [String]:
                result[key] = strings
            case let string as String:
                result[key] = [string]
            default:
                result[key] = [String(describing: value)]
            }
        }
        return result.isEmpty ? ["non_field_errors": ["Не удалось выполнить запрос"]] : result
    }
}

/// Заглушка для эндпоинтов, отдающих 204.
public struct EmptyResponse: Codable, Sendable {
    public init() {}
}
