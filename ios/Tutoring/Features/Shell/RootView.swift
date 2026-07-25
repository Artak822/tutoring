import SwiftUI
import TutoringCore

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(StudentsStore.self) private var studentsStore
    @Environment(GroupsStore.self) private var groupsStore
    @Environment(OfflineCache.self) private var cache
    @Environment(AppLock.self) private var appLock
    @Environment(LessonReminders.self) private var reminders

    var body: some View {
        content
            .overlay {
                if appLock.isLocked {
                    LockScreen()
                        .transition(.opacity)
                }
            }
            .onChange(of: session.state) { _, state in
                // Хранилища живут дольше сессии, поэтому чистим их руками на выходе
                if case .signedOut = state {
                    calendarStore.reset()
                    studentsStore.reset()
                    groupsStore.reset()
                    cache.clear()
                    reminders.cancelAll()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .launching:
            LaunchView()
        case .signedOut:
            LoginView()
                .transition(.opacity)
        case .signedIn:
            MainTabView()
                .transition(.opacity)
        }
    }
}

/// Пока проверяем сохранённый токен — короткая заставка вместо мигания экраном входа.
private struct LaunchView: View {
    var body: some View {
        VStack(spacing: Spacing.xl) {
            AppMark()
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground)
    }
}

struct MainTabView: View {
    var body: some View {
        // `Tab { }` из iOS 18 не используем — минимальная версия приложения 17.0
        TabView {
            CalendarScreen()
                .tabItem { Label("Календарь", systemImage: "calendar") }

            StudentsScreen()
                .tabItem { Label("Ученики", systemImage: "person.2") }

            ReportsScreen()
                .tabItem { Label("Отчёты", systemImage: "chart.bar") }

            SettingsScreen()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
