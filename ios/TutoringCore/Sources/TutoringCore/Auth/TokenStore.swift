import Foundation
import Security

/// Хранилище токена DRF. Токены бессрочные, поэтому лежат в Keychain, а не в UserDefaults:
/// бэкап устройства и файловая система не должны их отдавать.
public protocol TokenStoring: Sendable {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

public final class KeychainTokenStore: TokenStoring, @unchecked Sendable {
    private let service: String
    private let account: String
    private let accessGroup: String?
    private let lock = NSLock()

    public init(
        service: String = "app.tutoring.api",
        account: String = "auth-token",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func read() -> String? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String) {
        lock.lock()
        defer { lock.unlock() }

        let data = Data(token.utf8)
        let query = baseQuery()

        // AfterFirstUnlock, а не WhenUnlocked: виджету и фоновым обновлениям
        // токен нужен, когда экран заблокирован.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

/// Для тестов и превью — токен живёт в памяти.
public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func write(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}
