import SwiftUI
import TutoringCore

/// Ссылка на занятие по одному id — из карточки ученика занятие целиком не приходит,
/// а `LessonDetailScreen` всё равно грузит его сам.
struct LessonLink: Hashable {
    let id: Int
}

/// Карточка ученика: контакты, деньги, статистика, история занятий и оплат.
struct StudentDetailScreen: View {
    let studentId: Int

    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var store
    @Environment(GroupsStore.self) private var groupsStore
    @Environment(OfflineCache.self) private var cache
    @Environment(\.dismiss) private var dismiss

    @State private var student: Student?
    @State private var history: StudentHistory?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var cachedAt: Date?
    @State private var actionError: String?
    @State private var isShowingEdit = false
    @State private var isShowingClearDebts = false
    @State private var isConfirmingArchive = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let student, let history {
                content(student, history)
            } else if let loadError {
                ErrorStateView(message: loadError) { Task { await load() } }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(student?.fullName ?? "Ученик")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if student != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Изменить", systemImage: "pencil") { isShowingEdit = true }
                        Button("В архив", systemImage: "archivebox") { isConfirmingArchive = true }
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationDestination(for: LessonLink.self) { link in
            LessonDetailScreen(lessonId: link.id)
        }
        .sheet(isPresented: $isShowingEdit) {
            if let student {
                StudentFormScreen(mode: .edit(student)) {
                    await store.load()
                    await load(silently: true)
                }
            }
        }
        .sheet(isPresented: $isShowingClearDebts) {
            if let student {
                ClearDebtsSheet(student: student) {
                    await store.refreshQuietly()
                    await load(silently: true)
                }
            }
        }
        .task {
            await groupsStore.loadIfNeeded()
            await load()
        }
        .refreshable { await load(silently: true) }
        .alert("Убрать в архив?", isPresented: $isConfirmingArchive) {
            Button("В архив") { Task { await archive() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Ученик пропадёт из списков и форм, но занятия и оплаты сохранятся.")
        }
        .alert("Удалить ученика?", isPresented: $isConfirmingDelete) {
            Button("Удалить", role: .destructive) { Task { await delete() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вместе с учеником пропадут его занятия, оплаты и вся история.")
        }
        .alert("Не получилось", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Содержимое

    @ViewBuilder
    private func content(_ student: Student, _ history: StudentHistory) -> some View {
        List {
            if loadError != nil, let cachedAt {
                OfflineNoticeView(updatedAt: cachedAt)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            headerSection(student)
            contactsSection(student)
            moneySection(history.stats)
            statsSection(history.stats)
            lessonsSection(history.lessons)
            paymentsSection(history.payments)

            if !student.notes.isEmpty {
                Section("Заметки") {
                    Text(student.notes)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Шапка карточки: аватар, имя и состояние счёта одним взглядом.
    /// Без неё экран открывается сразу списком строк «Класс — Телефон — Цена»,
    /// и главный вопрос «должен ли он мне» приходится искать в середине.
    private func headerSection(_ student: Student) -> some View {
        Section {
            VStack(spacing: Spacing.m) {
                StudentAvatar(name: student.fullName, size: 64, tint: balanceTint(student))

                VStack(spacing: 2) {
                    Text(student.fullName)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if let grade = student.grade, !grade.isEmpty {
                        Text(grade)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                switch student.balanceState {
                case .debt(let amount):
                    Badge(
                        text: "Долг \(amount.formatted(currency: session.currency))",
                        systemImage: "exclamationmark.circle",
                        tint: Palette.debt
                    )
                case .prepaid(let amount):
                    Badge(
                        text: "Предоплата \(amount.formatted(currency: session.currency))",
                        systemImage: "wallet.bifold",
                        tint: Palette.prepaid
                    )
                case .clear:
                    Badge(text: "Расчёт закрыт", systemImage: "checkmark.circle", tint: Palette.prepaid)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.m)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func balanceTint(_ student: Student) -> Color {
        switch student.balanceState {
        case .debt: Palette.debt
        case .prepaid: Palette.prepaid
        case .clear: Palette.brand
        }
    }

    @ViewBuilder
    private func contactsSection(_ student: Student) -> some View {
        Section {
            if let grade = student.grade, !grade.isEmpty {
                LabeledContent("Класс", value: grade)
            }
            if let phone = student.phone, !phone.isEmpty {
                LabeledContent("Телефон") {
                    // tel: работает только на устройстве, но в симуляторе просто ничего не делает
                    Link(phone, destination: URL(string: "tel:\(phone.filter { !$0.isWhitespace })")!)
                }
            }
            if let telegram = student.telegram, !telegram.isEmpty {
                LabeledContent("Телеграм") {
                    Link(telegram, destination: telegramURL(telegram))
                }
            }
            if let price = student.defaultPrice {
                LabeledContent("Цена по умолчанию") {
                    Text(price.formatted(currency: session.currency))
                        .font(.tabular(.body))
                }
            }
            // Названия групп знает только их хранилище — у ученика лежат одни id
            let groups = groupsStore.names(for: student.groups)
            if !groups.isEmpty {
                LabeledContent("Группы", value: groups)
            }
        }
    }

    @ViewBuilder
    private func moneySection(_ stats: StudentHistory.Stats) -> some View {
        Section("Деньги") {
            LabeledContent("Оплачено всего") {
                Text(stats.totalPaid.formatted(currency: session.currency))
                    .font(.tabular(.body, weight: .semibold))
            }

            if stats.totalDebt.isPositive {
                LabeledContent("Долг") {
                    Text(stats.totalDebt.formatted(currency: session.currency))
                        .font(.tabular(.body, weight: .semibold))
                        .foregroundStyle(Palette.debt)
                }
                Button("Погасить долг") { isShowingClearDebts = true }
            }

            if stats.prepaidBalance.isPositive {
                LabeledContent("Предоплата") {
                    Text(stats.prepaidBalance.formatted(currency: session.currency))
                        .font(.tabular(.body, weight: .semibold))
                        .foregroundStyle(Palette.prepaid)
                }
            }
        }
    }

    @ViewBuilder
    private func statsSection(_ stats: StudentHistory.Stats) -> some View {
        Section("Занятия") {
            LabeledContent("Всего", value: String(stats.totalLessons))
            LabeledContent("Посетил", value: String(stats.presentLessons))
            LabeledContent("Пропустил", value: String(stats.absentLessons))
        }
    }

    @ViewBuilder
    private func lessonsSection(_ lessons: [StudentHistory.LessonRow]) -> some View {
        Section("История занятий") {
            if lessons.isEmpty {
                Text("Занятий пока не было")
                    .foregroundStyle(.secondary)
            }
            ForEach(lessons) { row in
                NavigationLink(value: LessonLink(id: row.lessonId)) {
                    StudentLessonRow(row: row, currency: session.currency)
                }
            }
        }
    }

    @ViewBuilder
    private func paymentsSection(_ payments: [StudentHistory.PaymentRecord]) -> some View {
        if !payments.isEmpty {
            Section {
                ForEach(payments) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateText.full(payment.paymentDate))
                            Text(payment.isBalance ? "С предоплаты" : payment.methodDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(payment.amount.formatted(currency: session.currency))
                            .font(.tabular(.body, weight: .semibold))
                    }
                }
            } header: {
                Text("Последние оплаты")
            } footer: {
                Text("Показаны 10 последних.")
            }
        }
    }

    private func telegramURL(_ handle: String) -> URL {
        let name = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return URL(string: "https://t.me/\(name)") ?? URL(string: "https://t.me")!
    }

    // MARK: - Данные

    private func load(silently: Bool = false) async {
        if !silently { isLoading = true }
        defer { isLoading = false }

        if student == nil { restoreFromCache() }

        do {
            async let studentRequest = session.api.student(studentId)
            async let historyRequest = session.api.studentHistory(studentId)
            let (loadedStudent, loadedHistory) = try await (studentRequest, historyRequest)
            student = loadedStudent
            history = loadedHistory
            loadError = nil
            cachedAt = nil
            cache.write(loadedStudent, for: CacheKey.student(studentId))
            cache.write(loadedHistory, for: CacheKey.studentHistory(studentId))
        } catch is CancellationError {
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Карточка, открытая раньше, остаётся доступной без сети.
    /// Дозвониться и посмотреть долг важнее, чем гарантия свежести цифр.
    private func restoreFromCache() {
        guard let cachedStudent = cache.read(Student.self, for: CacheKey.student(studentId)),
              let cachedHistory = cache.read(
                  StudentHistory.self, for: CacheKey.studentHistory(studentId)
              ) else { return }
        student = cachedStudent.value
        history = cachedHistory.value
        cachedAt = cachedStudent.updatedAt
    }

    private func archive() async {
        do {
            try await session.api.archiveStudent(studentId)
            await store.load()
            dismiss()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete() async {
        do {
            try await session.api.deleteStudent(studentId)
            await store.load()
            dismiss()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Строка занятия в карточке ученика: дата, статус отметки и статус оплаты.
struct StudentLessonRow: View {
    let row: StudentHistory.LessonRow
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.dayMonth(row.date))
                    .font(.body)
                Text(row.time.serverValue)
                    .font(.tabular(.caption))
                    .foregroundStyle(.secondary)
            }
            // Минимум вместо жёсткой ширины: при крупном системном шрифте
            // «23 сентября» в 96 точек уже не помещается.
            .frame(minWidth: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !row.subject.isEmpty {
                    Text(row.subject)
                        .font(.subheadline)
                }
                HStack(spacing: Spacing.s) {
                    statusBadge
                    Text(row.lessonPrice.formatted(currency: currency))
                        .font(.tabular(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if row.status == .cancelled {
            Badge(text: "Отменено", systemImage: "xmark.circle", tint: Palette.muted)
        } else if let payment = row.payment {
            Badge(
                text: payment.isBalance ? "С предоплаты" : "Оплачено",
                systemImage: "checkmark.circle",
                tint: Palette.prepaid
            )
        } else if row.isUnpaid {
            Badge(text: "Долг", systemImage: "exclamationmark.circle", tint: Palette.debt)
        } else if row.attendanceStatus == .absent {
            Badge(text: "Не был", systemImage: "person.slash", tint: Palette.muted)
        } else {
            Badge(text: "Не отмечен", systemImage: "circle.dashed", tint: Palette.muted)
        }
    }
}

/// Погашение всех долгов ученика разом — тот же экран, что `clear_all_debts` в вебе.
struct ClearDebtsSheet: View {
    let student: Student
    let onDone: () async -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var method: PaymentMethod = .cash
    @State private var date = CalendarDate.today(calendar: DateText.calendar)
    @State private var notes = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var result: ClearDebtsResult?

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSection(result)
                } else {
                    formSections
                }
            }
            .navigationTitle(result == nil ? "Погасить долг" : "Готово")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Погасить", action: submit)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Закрыть") { dismiss() }
                    }
                }
            }
            .busy(isBusy)
        }
    }

    @ViewBuilder
    private var formSections: some View {
        Section {
            LabeledContent("Ученик", value: student.fullName)
            LabeledContent("Долг") {
                Text(student.totalDebt.formatted(currency: session.currency))
                    .font(.tabular(.body, weight: .semibold))
                    .foregroundStyle(Palette.debt)
            }
        } footer: {
            if student.prepaidBalance.isPositive {
                Text("Сначала спишем предоплату \(student.prepaidBalance.formatted(currency: session.currency)), остаток проведём выбранным способом.")
            }
        }

        Section {
            Picker("Способ", selection: $method) {
                // Списание с баланса сервер делает сам, руками его выбрать нельзя
                Text(session.label(forPaymentMethod: .cash)).tag(PaymentMethod.cash)
                Text(session.label(forPaymentMethod: .transfer)).tag(PaymentMethod.transfer)
            }
            .pickerStyle(.segmented)

            DatePicker(
                "Дата оплаты",
                selection: Binding(
                    get: { date.date(in: DateText.calendar) },
                    set: { date = CalendarDate(date: $0, calendar: DateText.calendar) }
                ),
                displayedComponents: .date
            )

            TextField("Комментарий", text: $notes, axis: .vertical)
                .lineLimit(1...3)
        }

        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.debt)
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ result: ClearDebtsResult) -> some View {
        Section {
            LabeledContent("Погашено") {
                Text(result.totalDebt.formatted(currency: session.currency))
                    .font(.tabular(.body, weight: .semibold))
            }
            if result.paidFromBalanceCount > 0 {
                LabeledContent("С предоплаты") {
                    Text("\(result.paidFromBalanceAmount.formatted(currency: session.currency)) · \(plural(result.paidFromBalanceCount, "занятие", "занятия", "занятий"))")
                        .font(.tabular(.subheadline))
                }
            }
            if result.paymentsCreated > 0 {
                LabeledContent(session.label(forPaymentMethod: method)) {
                    Text("\(result.paymentsAmount.formatted(currency: session.currency)) · \(plural(result.paymentsCreated, "занятие", "занятия", "занятий"))")
                        .font(.tabular(.subheadline))
                }
            }
            LabeledContent("Остаток долга") {
                Text(result.totalDebtLeft.formatted(currency: session.currency))
                    .font(.tabular(.body))
            }
            LabeledContent("Баланс предоплаты") {
                Text(result.studentBalance.formatted(currency: session.currency))
                    .font(.tabular(.body))
            }
        }
    }

    private func submit() {
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                result = try await session.api.clearDebts(
                    studentId: student.id,
                    method: method,
                    date: date,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await onDone()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
