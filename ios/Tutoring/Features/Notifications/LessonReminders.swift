import Foundation
import Observation
import TutoringCore
import UserNotifications

/// Локальные напоминания о занятиях.
///
/// Пуши с сервера тут не нужны: расписание уже лежит на устройстве, а занятие
/// известно заранее. Локальное уведомление срабатывает и без сети — ровно тогда,
/// когда репетитор о нём и вспоминает.
@MainActor
@Observable
final class LessonReminders {
    private enum Key {
        static let isEnabled = "reminders.isEnabled"
        static let minutesBefore = "reminders.minutesBefore"
    }

    /// Сколько уведомлений iOS держит на одно приложение. Всё сверх лимита
    /// система молча выбрасывает, поэтому режем сами — с ближайших занятий.
    private static let systemLimit = 60

    static let availableOffsets = [10, 15, 30, 60]

    private(set) var isEnabled: Bool
    private(set) var minutesBefore: Int

    /// Пользователь запретил уведомления в настройках системы — переключатель
    /// в приложении в этом случае врёт, поэтому показываем подсказку.
    private(set) var isDeniedBySystem = false

    /// Сколько напоминаний стоит в очереди. Без этой цифры включённый
    /// переключатель ничего не обещает: занятий может не быть вовсе.
    private(set) var scheduledCount = 0

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let presenter = ForegroundPresenter()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        let stored = defaults.integer(forKey: Key.minutesBefore)
        minutesBefore = Self.availableOffsets.contains(stored) ? stored : 30
        center.delegate = presenter
    }

    /// Проверяем разрешение при каждом открытии настроек: его могли отозвать
    /// снаружи, и тогда включённый переключатель ничего не значит.
    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isDeniedBySystem = settings.authorizationStatus == .denied
    }

    /// Включение спрашивает разрешение; отказ возвращает переключатель обратно.
    func setEnabled(_ enabled: Bool, lessons: [Lesson], studentNames: (Lesson) -> String) async {
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Key.isEnabled)
            center.removeAllPendingNotificationRequests()
            scheduledCount = 0
            return
        }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        isEnabled = granted
        isDeniedBySystem = !granted
        defaults.set(granted, forKey: Key.isEnabled)

        if granted {
            await reschedule(lessons: lessons, studentNames: studentNames)
        }
    }

    func setMinutesBefore(_ minutes: Int, lessons: [Lesson], studentNames: (Lesson) -> String) async {
        minutesBefore = minutes
        defaults.set(minutes, forKey: Key.minutesBefore)
        await reschedule(lessons: lessons, studentNames: studentNames)
    }

    /// Перепланировать всё заново.
    ///
    /// Занятия правятся и отменяются часто, а вычислять разницу между тем, что
    /// уже стоит в очереди, и тем, что должно стоять, — сложнее и легко разъезжается.
    /// Полсотни уведомлений система переваривает мгновенно.
    func reschedule(lessons: [Lesson], studentNames: (Lesson) -> String) async {
        center.removeAllPendingNotificationRequests()
        guard isEnabled else {
            scheduledCount = 0
            return
        }

        let now = Date.now
        let upcoming = lessons
            .filter { !$0.isCancelled }
            .compactMap { lesson -> (Lesson, Date)? in
                let fireDate = lesson.startsAt.addingTimeInterval(-Double(minutesBefore * 60))
                // Занятие уже началось или напоминать поздно — пропускаем
                guard fireDate > now else { return nil }
                return (lesson, fireDate)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.systemLimit)

        for (lesson, fireDate) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Занятие через \(minutesLabel)"
            content.body = body(for: lesson, names: studentNames(lesson))
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: "lesson.\(lesson.id)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }

        scheduledCount = upcoming.count
    }

    /// Выход из аккаунта: чужие занятия не должны всплывать у следующего владельца
    /// устройства. Настройку при этом сохраняем — вернётся вместе со входом.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        scheduledCount = 0
    }

    private var minutesLabel: String {
        minutesBefore < 60 ? "\(minutesBefore) мин" : "час"
    }

    /// Уведомление, пришедшее при открытом приложении, iOS по умолчанию
    /// проглатывает. Но расписание как раз и держат открытым перед занятием —
    /// именно там напоминание нужнее всего, поэтому показываем баннер всегда.
    ///
    /// Собственного состояния у делегата нет, поэтому `@unchecked Sendable`
    /// здесь безопасен.
    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate,
        @unchecked Sendable
    {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound, .list]
        }
    }

    private func body(for lesson: Lesson, names: String) -> String {
        let time = lesson.time.displayValue
        let subject = lesson.subject.isEmpty ? "" : " · \(lesson.subject)"
        return names.isEmpty ? "\(time)\(subject)" : "\(time) — \(names)\(subject)"
    }
}
