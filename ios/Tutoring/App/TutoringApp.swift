import SwiftUI

@main
struct TutoringApp: App {
    @State private var session: Session
    @State private var calendarStore: CalendarStore
    @State private var studentsStore: StudentsStore
    @State private var groupsStore: GroupsStore
    @State private var cache: OfflineCache
    @State private var appLock = AppLock()
    @State private var reminders = LessonReminders()

    @Environment(\.scenePhase) private var scenePhase

    /// Хранилища строятся здесь, а не внутри экранов: они переживают переключение
    /// вкладок и держат общий на всё приложение `api` из сессии.
    init() {
        let cache = OfflineCache()
        let session = Session(cache: cache)
        _session = State(initialValue: session)
        _cache = State(initialValue: cache)
        _calendarStore = State(initialValue: CalendarStore(api: session.api, cache: cache))
        _studentsStore = State(initialValue: StudentsStore(api: session.api, cache: cache))
        _groupsStore = State(initialValue: GroupsStore(api: session.api, cache: cache))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(calendarStore)
                .environment(studentsStore)
                .environment(groupsStore)
                .environment(cache)
                .environment(appLock)
                .environment(reminders)
                .tint(Palette.brand)
                .task { await session.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Замок ставим на .inactive, а не .background: снимок для
                    // переключателя задач система делает раньше, чем фон.
                    guard phase == .active else {
                        appLock.lock()
                        return
                    }
                    // Спрашивать Face ID можно только у активного приложения:
                    // в фоне LocalAuthentication не покажет окно, и запрос
                    // просто сгорит впустую.
                    Task { await appLock.unlock() }
                }
        }
    }
}
