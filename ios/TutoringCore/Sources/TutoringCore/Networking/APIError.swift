import Foundation

/// Ошибки API в формулировках, которые можно показать пользователю.
/// Django отдаёт ошибки в двух видах: `{"error": "текст"}` от services.py и
/// `{"поле": ["ошибка"]}` от сериализаторов — разбираем оба.
public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden(String)
    case notFound
    case validation([String: [String]])
    case server(status: Int, message: String?)
    case offline
    case timeout
    case decoding(String)
    case transport(String)

    public var isAuthFailure: Bool {
        self == .unauthorized
    }

    /// Ошибка означает «данных нет прямо сейчас», а не «действие невозможно» —
    /// в этом случае показываем кэш вместо экрана ошибки.
    public var isConnectivity: Bool {
        switch self {
        case .offline, .timeout: true
        default: false
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Сессия истекла. Войдите заново."
        case .forbidden(let message):
            message.isEmpty ? "Недостаточно прав" : message
        case .notFound:
            "Запись не найдена"
        case .validation(let fields):
            Self.describe(fields)
        case .server(let status, let message):
            message ?? "Ошибка сервера (\(status))"
        case .offline:
            "Нет связи с сервером"
        case .timeout:
            "Сервер не отвечает"
        case .decoding:
            "Сервер вернул неожиданный ответ"
        case .transport(let message):
            message
        }
    }

    /// Техническая расшифровка — уходит только в лог, пользователю не показывается.
    public var diagnosticDescription: String {
        switch self {
        case .decoding(let details): "Ошибка разбора ответа: \(details)"
        case .server(let status, let message): "HTTP \(status): \(message ?? "—")"
        default: errorDescription ?? "\(self)"
        }
    }

    private static func describe(_ fields: [String: [String]]) -> String {
        // non_field_errors — общая ошибка формы, показываем её первой
        if let common = fields["non_field_errors"]?.first ?? fields["detail"]?.first {
            return common
        }
        return fields
            .sorted { $0.key < $1.key }
            .compactMap { key, messages in
                guard let message = messages.first else { return nil }
                return Self.fieldTitles[key].map { "\($0): \(message)" } ?? message
            }
            .joined(separator: "\n")
    }

    /// Русские названия полей — сообщения вида «username: обязательное поле»
    /// без этого выглядят как утечка внутренностей.
    private static let fieldTitles: [String: String] = [
        "username": "Логин",
        "password": "Пароль",
        "password1": "Пароль",
        "password2": "Подтверждение пароля",
        "email": "Email",
        "first_name": "Имя",
        "last_name": "Фамилия",
        "phone": "Телефон",
        "students": "Ученики",
        "date": "Дата",
        "time": "Время",
        "duration": "Длительность",
        "lesson_price": "Стоимость",
        "amount": "Сумма",
        "payment_method": "Способ оплаты",
        "period": "Период",
        "groups": "Группы",
    ]
}
