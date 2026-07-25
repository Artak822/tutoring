import SwiftUI
import TutoringCore

/// Настройки: напоминания, защита, профиль и выход.
///
/// Раньше эта вкладка называлась «Ещё» и была свалкой из сводки, отчётов и групп.
/// Цифры уехали в «Отчёты», группы — к ученикам, и осталось ровно то, что
/// настраивают один раз и забывают.
struct SettingsScreen: View {
    @Environment(Session.self) private var session
    @Environment(AppLock.self) private var appLock
    @Environment(LessonReminders.self) private var reminders
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(StudentsStore.self) private var studentsStore

    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            List {
                remindersSection
                securitySection

                if let tutor = session.tutor {
                    Section("Профиль") {
                        LabeledContent("Имя", value: tutor.displayName)
                        LabeledContent("Логин", value: tutor.username)
                        if let phone = tutor.phone, !phone.isEmpty {
                            LabeledContent("Телефон", value: phone)
                        }
                    }
                }

                Section("Подключение") {
                    LabeledContent("Сервер", value: session.environment.title)
                    LabeledContent("Адрес", value: session.environment.baseURL.host() ?? "—")
                    if let meta = session.meta {
                        LabeledContent("Версия API", value: meta.apiVersion)
                    }
                }

                Section {
                    Button("Выйти", role: .destructive) {
                        isSigningOut = true
                        Task {
                            await session.signOut()
                            isSigningOut = false
                        }
                    }
                }
            }
            .navigationTitle("Настройки")
            .busy(isSigningOut)
            .task { await reminders.refreshAuthorization() }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { reminders.isEnabled },
                set: { enabled in
                    Task { await setReminders(enabled: enabled) }
                }
            )) {
                HStack(spacing: Spacing.m) {
                    ShortcutIcon(systemImage: "bell.fill", tint: .orange)
                    Text("Напоминать о занятиях")
                }
            }

            if reminders.isEnabled {
                Picker("За сколько", selection: Binding(
                    get: { reminders.minutesBefore },
                    set: { minutes in
                        Task { await setReminderOffset(minutes) }
                    }
                )) {
                    ForEach(LessonReminders.availableOffsets, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) мин" : "1 час").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Напоминания")
        } footer: {
            if reminders.isDeniedBySystem {
                Text("Уведомления запрещены в настройках iOS. Разрешите их для «Репетитора», иначе напоминания не придут.")
            } else if reminders.isEnabled {
                Text("Уведомление приходит перед началом занятия и работает без интернета. \(scheduledText)")
            } else {
                Text("Уведомление приходит перед началом занятия. Работает без интернета.")
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        if appLock.isBiometryAvailable {
            Section {
                Toggle(isOn: Binding(
                    get: { appLock.isEnabled },
                    set: { appLock.setEnabled($0) }
                )) {
                    HStack(spacing: Spacing.m) {
                        ShortcutIcon(systemImage: appLock.biometrySymbol, tint: Palette.brand)
                        Text("Вход по \(appLock.biometryTitle)")
                    }
                }
            } header: {
                Text("Защита")
            } footer: {
                Text("Приложение будет запрашивать подтверждение при каждом открытии.")
            }
        }
    }

    /// Включённый переключатель сам по себе ничего не обещает: если ближайших
    /// занятий нет, очередь пуста — и лучше сказать это прямо.
    private var scheduledText: String {
        let count = reminders.scheduledCount
        guard count > 0 else { return "Пока напоминать не о чем — ближайших занятий нет." }
        return "Запланировано \(plural(count, "напоминание", "напоминания", "напоминаний"))."
    }

    private func setReminders(enabled: Bool) async {
        await reminders.setEnabled(enabled, lessons: calendarStore.allLessons) { lesson in
            studentsStore.names(for: lesson.students)
        }
    }

    private func setReminderOffset(_ minutes: Int) async {
        await reminders.setMinutesBefore(minutes, lessons: calendarStore.allLessons) { lesson in
            studentsStore.names(for: lesson.students)
        }
    }
}
