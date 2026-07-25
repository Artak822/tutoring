import Foundation

/// Куда ходит приложение. В Debug доступен локальный Django, в релизе — только стенд.
public struct ServerEnvironment: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let baseURL: URL

    public init(id: String, title: String, baseURL: URL) {
        self.id = id
        self.title = title
        self.baseURL = baseURL
    }

    /// Базовый URL API с версией: все `Endpoint.path` считаются относительными ему.
    public var apiRoot: URL {
        baseURL.appendingPathComponent("api/v1", isDirectory: true)
    }

    public static let production = ServerEnvironment(
        id: "production",
        title: "Основной сервер",
        baseURL: URL(string: "https://tutoringartak.up.railway.app")!
    )

    /// Симулятор ходит на localhost хоста напрямую. На реальном устройстве localhost —
    /// это сам телефон, поэтому там нужен IP машины (меняется в настройках сборки).
    public static let localhost = ServerEnvironment(
        id: "localhost",
        title: "Локальный Django",
        baseURL: URL(string: "http://localhost:8000")!
    )

    public static var availableEnvironments: [ServerEnvironment] {
        #if DEBUG
        [.production, .localhost]
        #else
        [.production]
        #endif
    }

    /// Основной стенд по умолчанию даже в отладке: приложение проверяют на живых
    /// данных, а локальный Django поднят не всегда — переключиться на него можно
    /// на экране входа.
    public static var `default`: ServerEnvironment { .production }
}
