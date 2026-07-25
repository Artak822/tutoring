import Foundation
import LocalAuthentication
import Observation

/// Блокировка приложения по Face ID / Touch ID.
///
/// Токен и так лежит в Keychain, а данные — на устройстве, поэтому замок здесь
/// не про безопасность канала, а про чужие руки: телефон часто дают ученику
/// посмотреть расписание, а в приложении видны долги и телефоны всех остальных.
@MainActor
@Observable
final class AppLock {
    private enum Key {
        static let isEnabled = "appLock.isEnabled"
    }

    /// Замок включён в настройках. Выключенный замок ничего не спрашивает.
    private(set) var isEnabled: Bool

    /// Экран закрыт шторкой и ждёт подтверждения личности.
    private(set) var isLocked = false

    /// Последняя неудача — показываем её на экране блокировки, а не алертом:
    /// алерт поверх шторки перекрывает единственную кнопку «Повторить».
    private(set) var failureMessage: String?

    /// Запрос уже показан. Без этого флага возврат из фона успевает дёрнуть
    /// проверку дважды, и второе окно Face ID отменяет первое.
    private var isAuthenticating = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        // Холодный старт с включённым замком — сразу за шторку, до первого кадра
        isLocked = isEnabled
    }

    /// Доступна ли на устройстве биометрия. Без неё переключатель прячем:
    /// предлагать «вход по Face ID» там, где его нет, — обещание впустую.
    var isBiometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        )
    }

    /// Face ID, Touch ID или Optic ID — подпись переключателя зависит от железа.
    var biometryTitle: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Биометрия"
        }
    }

    /// Значок под тот же тип биометрии, что и подпись: рисовать Face ID
    /// владельцу iPhone SE было бы враньём.
    var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.isEnabled)
        // Выключили — снимаем шторку, иначе она останется висеть до перезапуска
        if !enabled {
            isLocked = false
            failureMessage = nil
        }
    }

    /// Уход в фон. Шторку ставим здесь, а не при возврате: снимок экрана
    /// в переключателе задач не должен показывать чужие долги.
    func lock() {
        guard isEnabled else { return }
        isLocked = true
        failureMessage = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Отмена"

        do {
            // Политика с паролем устройства, а не только биометрия: иначе после
            // трёх неудачных попыток Face ID приложение запирается наглухо.
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Разблокируйте, чтобы открыть расписание"
            )
            if success {
                isLocked = false
                failureMessage = nil
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            // Пользователь сам закрыл окно — молча остаёмся под шторкой
            failureMessage = nil
        } catch {
            failureMessage = (error as? LAError).map(Self.message(for:))
                ?? error.localizedDescription
        }
    }

    private static func message(for error: LAError) -> String {
        switch error.code {
        case .biometryLockout: "Слишком много попыток. Введите код-пароль устройства."
        case .biometryNotAvailable: "Биометрия недоступна"
        case .biometryNotEnrolled: "Биометрия не настроена на устройстве"
        case .passcodeNotSet: "На устройстве не задан код-пароль"
        default: "Не удалось подтвердить личность"
        }
    }
}
