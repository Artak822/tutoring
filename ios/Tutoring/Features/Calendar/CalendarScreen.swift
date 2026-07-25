import SwiftUI
import TutoringCore

struct CalendarScreen: View {
    @Environment(Session.self) private var session
    @Environment(CalendarStore.self) private var store
    @Environment(StudentsStore.self) private var students
    @Environment(LessonReminders.self) private var reminders

    @State private var newLesson: LessonFormScreen.Mode?
    @State private var isShowingRecurring = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let cachedAt = store.offlineSince {
                    // Занятия на экране есть — значит это не сбой, а старые данные.
                    // Плашка живёт в потоке, а не поверх: она держится долго
                    // и иначе закрывала бы название месяца.
                    OfflineNoticeView(updatedAt: cachedAt)
                }

                monthHeader
                MonthGridView(
                    month: store.visibleMonth,
                    selectedDate: store.selectedDate,
                    lessonsProvider: store.lessons(on:),
                    onSelect: { store.selectedDate = $0 }
                )
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.s)

                Divider()

                dayList
            }
            // Заголовок пустой намеренно: название месяца крупно стоит прямо под
            // панелью, а слово «Календарь» уже написано на вкладке — третий повтор лишний.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сегодня") { goToToday() }
                        .disabled(isOnToday)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Новое занятие", systemImage: "plus") {
                            newLesson = .create(date: store.selectedDate)
                        }
                        Button("Серия занятий", systemImage: "repeat") {
                            isShowingRecurring = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Lesson.self) { lesson in
                LessonDetailScreen(lessonId: lesson.id)
            }
            .sheet(item: $newLesson) { mode in
                LessonFormScreen(mode: mode) { await reload() }
            }
            .sheet(isPresented: $isShowingRecurring) {
                RecurringLessonScreen(startDate: store.selectedDate) { await reload() }
            }
            .task { await initialLoad() }
            .refreshable { await reload() }
            .overlay(alignment: .top) {
                if store.offlineSince == nil, let message = store.errorMessage {
                    banner(message)
                }
            }
        }
    }

    // MARK: - Шапка месяца

    /// Месяц слева и крупно, стрелки — справа парой. Так название читается первым
    /// взглядом, а не ищется между двумя одинаковыми кнопками.
    private var monthHeader: some View {
        HStack(spacing: Spacing.s) {
            Text(DateText.monthTitle(year: store.visibleMonth.year, month: store.visibleMonth.month))
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            monthArrow("chevron.left", delta: -1)
            monthArrow("chevron.right", delta: 1)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.m)
    }

    private func monthArrow(_ systemImage: String, delta: Int) -> some View {
        Button {
            changeMonth(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.brand)
                .frame(width: 32, height: 32)
                .background(Palette.brandSurface, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Список дня

    private var dayList: some View {
        List {
            Section {
                if store.selectedDayLessons.isEmpty {
                    ContentUnavailableView {
                        Label("Занятий нет", systemImage: "calendar")
                    } description: {
                        Text("В этот день ничего не запланировано")
                    } actions: {
                        Button("Добавить занятие") {
                            newLesson = .create(date: store.selectedDate)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.selectedDayLessons) { lesson in
                        NavigationLink(value: lesson) {
                            LessonRow(
                                lesson: lesson,
                                studentNames: students.names(for: lesson.students),
                                currency: session.currency
                            )
                        }
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(DateText.relativeDay(store.selectedDate))
                        .font(.sectionTitle)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Spacer()
                    if !store.selectedDayLessons.isEmpty {
                        // Плановая выручка дня — то, ради чего в расписание
                        // заглядывают чаще всего после самих занятий.
                        Text(dayTotal)
                            .font(.tabular(.subheadline, weight: .semibold))
                            .foregroundStyle(Palette.brand)
                            .textCase(nil)
                    }
                }
                .padding(.bottom, Spacing.xs)
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Сумма дня — плановая, по неотменённым занятиям. Фактический заработок
    /// зависит от отметок и живёт в отчёте по прибыли.
    private var dayTotal: String {
        let total = store.selectedDayLessons
            .filter { !$0.isCancelled }
            .reduce(Money.zero) { $0 + $1.plannedPrice }
        return total.formatted(currency: session.currency)
    }

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity)
            .background(Palette.debt, in: RoundedRectangle(cornerRadius: Radius.control))
            .padding(Spacing.m)
    }

    // MARK: - Действия

    private var isOnToday: Bool {
        let today = CalendarDate.today(calendar: DateText.calendar)
        return store.selectedDate == today
            && store.visibleMonth == CalendarStore.MonthKey(year: today.year, month: today.month)
    }

    private func goToToday() {
        let today = CalendarDate.today(calendar: DateText.calendar)
        withAnimation {
            store.visibleMonth = CalendarStore.MonthKey(year: today.year, month: today.month)
            store.selectedDate = today
        }
        Task { await store.loadIfNeeded(store.visibleMonth) }
    }

    private func changeMonth(by delta: Int) {
        let next = store.visibleMonth.advanced(by: delta)
        withAnimation {
            store.visibleMonth = next
            // Выбранный день переносим на то же число нового месяца, если оно существует
            let lastDay = CalendarDate(year: next.year, month: next.month, day: 1)
                .endOfMonth(calendar: DateText.calendar).day
            store.selectedDate = CalendarDate(
                year: next.year, month: next.month, day: min(store.selectedDate.day, lastDay)
            )
        }
        Task { await store.loadIfNeeded(next) }
    }

    private func initialLoad() async {
        async let calendar: Void = store.loadIfNeeded(store.visibleMonth)
        async let studentsList: Void = students.loadIfNeeded()
        _ = await (calendar, studentsList)

        // Следующий месяц нужен напоминаниям: в последних числах все ближайшие
        // занятия лежат уже в нём, а листать календарь ради этого никто не станет.
        await store.loadIfNeeded(store.visibleMonth.advanced(by: 1))
        await rescheduleReminders()
    }

    private func reload() async {
        await store.reloadVisibleMonth()
        await students.refreshQuietly()
        await rescheduleReminders()
    }

    private func rescheduleReminders() async {
        await reminders.reschedule(lessons: store.allLessons) { lesson in
            students.names(for: lesson.students)
        }
    }
}
