import SwiftUI
import TutoringCore

/// Карточка занятия и быстрое закрытие: отметить присутствие, принять оплату,
/// отменить или восстановить. Всё, что меняет ученика, идёт через `quick-action/`
/// — тот же эндпоинт, что дёргает веб-версия.
struct LessonDetailScreen: View {
    let lessonId: Int

    @Environment(Session.self) private var session
    @Environment(CalendarStore.self) private var calendar
    @Environment(OfflineCache.self) private var cache
    @Environment(\.dismiss) private var dismiss

    @State private var lesson: Lesson?
    @State private var state: LessonState?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var cachedAt: Date?
    @State private var actionError: String?

    /// Пока запрос по ученику в полёте, его строка заблокирована — иначе
    /// двойной тап успевает отправить два действия подряд.
    @State private var busyStudentId: Int?

    @State private var isShowingCancel = false
    @State private var isShowingEdit = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let lesson, let state {
                content(lesson: lesson, state: state)
            } else if let loadError {
                ErrorStateView(message: loadError) {
                    Task { await load() }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(lesson.map { DateText.relativeDay($0.date) } ?? "Занятие")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if lesson != nil {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
        }
        .task { await load() }
        .refreshable { await load(silently: true) }
        .sheet(isPresented: $isShowingCancel) {
            CancelLessonSheet(reasons: session.meta?.cancellationReasons ?? []) { reason, note in
                await cancel(reason: reason, note: note)
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            if let lesson {
                LessonFormScreen(mode: .edit(lesson)) {
                    // Занятие могло переехать на другую дату — кэш месяцев чистим целиком.
                    calendar.invalidateAll()
                    await calendar.load(calendar.visibleMonth)
                    await load(silently: true)
                }
            }
        }
        .alert("Удалить занятие?", isPresented: $isConfirmingDelete) {
            Button("Удалить", role: .destructive) { Task { await delete() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Оплаты и отметки посещаемости по этому занятию тоже пропадут.")
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

    private func content(lesson: Lesson, state: LessonState) -> some View {
        List {
            if loadError != nil, let cachedAt {
                OfflineNoticeView(updatedAt: cachedAt)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Ученики выше справки: занятие открывают, чтобы закрыть его, а дата
            // и цена в этот момент уже известны — им место под списком.
            if lesson.isCancelled {
                Section {
                    cancelledNotice(lesson)
                }
            } else {
                Section("Ученики") {
                    ForEach(state.students) { student in
                        StudentQuickCloseRow(
                            student: student,
                            lessonPrice: state.lessonPrice,
                            currency: session.currency,
                            cashLabel: session.label(forPaymentMethod: .cash),
                            transferLabel: session.label(forPaymentMethod: .transfer),
                            isBusy: busyStudentId == student.studentId,
                            onMarkPresent: { await run(.markPresent(student: student.studentId), for: student.studentId) },
                            onMarkAbsent: { await run(.markAbsent(student: student.studentId), for: student.studentId) },
                            onPay: { amount, method in
                                await run(
                                    .addPayment(student: student.studentId, amount: amount, method: method),
                                    for: student.studentId
                                )
                            },
                            onResetPayment: { await run(.resetPayment(student: student.studentId), for: student.studentId) }
                        )
                    }
                }
            }

            summarySection(lesson: lesson, state: state)

            if !lesson.notes.isEmpty {
                Section("Заметки") {
                    Text(lesson.notes)
                }
            }
        }
        .listStyle(.insetGrouped)
        // Сумма правится прямо в строке, и убрать цифровую клавиатуру иначе
        // нечем: у decimalPad нет кнопки возврата.
        .scrollDismissesKeyboard(.interactively)
    }

    private func summarySection(lesson: Lesson, state: LessonState) -> some View {
        Section {
            LabeledContent("Дата") { Text(DateText.full(lesson.date)) }
            LabeledContent("Время") {
                Text(DateText.timeRange(start: lesson.time, durationMinutes: lesson.duration))
                    .font(.tabular(.body))
            }
            if !lesson.subject.isEmpty {
                LabeledContent("Предмет") { Text(lesson.subject) }
            }
            LabeledContent("Цена с ученика") {
                Text(state.lessonPrice.formatted(currency: session.currency))
                    .font(.tabular(.body))
            }
            if !lesson.isCancelled {
                // Сервер считает totalPrice по отмеченным ученикам, а не по всем
                LabeledContent("К оплате за пришедших") {
                    Text(state.totalPrice.formatted(currency: session.currency))
                        .font(.tabular(.body, weight: .semibold))
                }
                LabeledContent("Присутствуют") {
                    Text("\(state.presentCount) из \(state.students.count)")
                        .font(.tabular(.body))
                }
            }
        } header: {
            // Заголовок появился вместе с переездом вниз: без него справка
            // читалась как продолжение списка учеников.
            Text("Занятие")
        }
    }

    private func cancelledNotice(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Badge(
                text: lesson.cancellationReasonDisplay ?? "Занятие отменено",
                systemImage: "xmark.circle",
                tint: Palette.muted
            )
            if !lesson.cancellationNote.isEmpty {
                Text(lesson.cancellationNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Оплаты по отменённому занятию возвращены на баланс учеников.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Восстановить занятие") {
                Task { await restore() }
            }
            .buttonStyle(.outline)
            .padding(.top, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs)
    }

    private var menu: some View {
        Menu {
            Button("Редактировать", systemImage: "pencil") { isShowingEdit = true }

            if lesson?.isCancelled == true {
                Button("Восстановить", systemImage: "arrow.uturn.backward") {
                    Task { await restore() }
                }
            } else {
                Button("Отменить занятие", systemImage: "xmark.circle") {
                    isShowingCancel = true
                }
            }

            Divider()

            Button("Удалить", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(isLoading)
    }

    // MARK: - Загрузка

    /// `silently` — для pull-to-refresh: экран уже с данными, спиннер не нужен.
    private func load(silently: Bool = false) async {
        if !silently { isLoading = true }
        defer { isLoading = false }

        if lesson == nil { restoreFromCache() }

        do {
            async let lessonRequest = session.api.lesson(lessonId)
            async let stateRequest = session.api.lessonState(lessonId)
            let (loadedLesson, loadedState) = try await (lessonRequest, stateRequest)
            lesson = loadedLesson
            state = loadedState
            loadError = nil
            cachedAt = nil
            cache.write(loadedLesson, for: CacheKey.lesson(lessonId))
            cache.write(loadedState, for: CacheKey.lessonState(lessonId))
        } catch is CancellationError {
            // Ушли с экрана до ответа — молчим
        } catch {
            loadError = message(for: error)
        }
    }

    /// Без сети занятие показываем таким, каким видели его в прошлый раз:
    /// состав и время нужны и в дороге. Отметки и оплаты при этом уйдут в ошибку —
    /// они меняют данные, а кэш только читает.
    private func restoreFromCache() {
        guard let cachedLesson = cache.read(Lesson.self, for: CacheKey.lesson(lessonId)),
              let cachedState = cache.read(LessonState.self, for: CacheKey.lessonState(lessonId))
        else { return }
        lesson = cachedLesson.value
        state = cachedState.value
        cachedAt = cachedLesson.updatedAt
    }

    // MARK: - Действия по ученику

    private func run(_ action: QuickAction, for studentId: Int) async {
        busyStudentId = studentId
        defer { busyStudentId = nil }

        do {
            let result = try await session.api.quickAction(lessonId: lessonId, action)
            apply(result, to: studentId)
        } catch {
            actionError = message(for: error)
            // Ответ мог частично примениться на сервере — сверяемся с ним.
            await load(silently: true)
        }
    }

    /// Ответ quick-action содержит всё, что меняется в строке, поэтому список
    /// не перезапрашиваем: обновляем ученика на месте и пересчитываем шапку.
    private func apply(_ result: QuickActionResult, to studentId: Int) {
        guard var current = state,
              let index = current.students.firstIndex(where: { $0.studentId == studentId })
        else { return }

        let old = current.students[index]
        var students = current.students
        students[index] = LessonStudentState(
            studentId: old.studentId,
            firstName: old.firstName,
            lastName: old.lastName,
            attendanceStatus: result.attendanceStatus,
            payment: result.payment,
            studentBalance: result.studentBalance
        )

        let presentCount = students.filter { $0.attendanceStatus == .present }.count
        current = LessonState(
            lessonId: current.lessonId,
            lessonPrice: result.lessonPrice,
            status: current.status,
            presentCount: presentCount,
            totalPrice: (0..<presentCount).reduce(Money.zero) { sum, _ in sum + result.lessonPrice },
            students: students
        )
        state = current
    }

    // MARK: - Действия по занятию

    private func cancel(reason: String, note: String) async {
        do {
            let change = try await session.api.cancelLesson(lessonId, reason: reason, note: note)
            applyStatus(change)
            await calendar.reloadVisibleMonth()
            await load(silently: true)
        } catch {
            actionError = message(for: error)
        }
    }

    private func restore() async {
        do {
            let change = try await session.api.restoreLesson(lessonId)
            applyStatus(change)
            await calendar.reloadVisibleMonth()
            await load(silently: true)
        } catch {
            actionError = message(for: error)
        }
    }

    /// Сервер возвращает только изменившиеся поля, поэтому статус подменяем
    /// вручную — до того, как придёт полная перезагрузка.
    private func applyStatus(_ change: LessonStatusChange) {
        guard let current = lesson else { return }
        lesson = Lesson(
            id: current.id,
            students: current.students,
            date: current.date,
            time: current.time,
            duration: current.duration,
            lessonPrice: current.lessonPrice,
            subject: current.subject,
            notes: current.notes,
            status: change.status,
            cancellationReason: change.reason ?? "",
            cancellationReasonDisplay: change.reasonDisplay,
            cancellationNote: change.note ?? "",
            presentStudentsCount: current.presentStudentsCount,
            totalPrice: current.totalPrice
        )
    }

    private func delete() async {
        do {
            try await session.api.deleteLesson(lessonId)
            await calendar.reloadVisibleMonth()
            dismiss()
        } catch {
            actionError = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Строка ученика

/// Одна строка быстрого закрытия — как в вебе: отметка, потом деньги.
///
/// Шагов ровно два, и каждый следующий появляется, только когда сделан
/// предыдущий: пара «Был / Не был» после выбора сворачивается в один чип,
/// а под ней раскрывается сумма с двумя способами оплаты. Пустых полей на
/// экране не висит — занятие закрывается двумя касаниями, не открывая листов.
private struct StudentQuickCloseRow: View {
    let student: LessonStudentState
    let lessonPrice: Money
    let currency: String
    let cashLabel: String
    let transferLabel: String
    let isBusy: Bool
    let onMarkPresent: () async -> Void
    let onMarkAbsent: () async -> Void
    let onPay: (Money, PaymentMethod) async -> Void
    let onResetPayment: () async -> Void

    /// Свёрнутый чип раскрыт обратно в пару кнопок — когда отметку надо переставить.
    @State private var isChangingAttendance = false
    @State private var amountText = ""
    @FocusState private var isAmountFocused: Bool

    private var amount: Money? {
        Money(string: amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var overpayment: Money? {
        guard let amount, amount > lessonPrice else { return nil }
        return amount - lessonPrice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                StudentAvatar(name: student.fullName, size: 32)
                Text(student.fullName)
                    .font(.body.weight(.medium))
                Spacer(minLength: Spacing.s)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            attendanceControl

            if student.attendanceStatus == .present {
                paymentControl
            }

            if student.studentBalance.isPositive {
                Text("Предоплата: \(student.studentBalance.formatted(currency: currency))")
                    .font(.caption)
                    .foregroundStyle(Palette.prepaid)
            }
        }
        .padding(.vertical, Spacing.xs)
        .disabled(isBusy)
        .animation(.snappy(duration: 0.22), value: student.attendanceStatus)
        .animation(.snappy(duration: 0.22), value: student.payment)
        .onAppear { amountText = lessonPrice.formattedForServer }
        .onChange(of: lessonPrice) { _, price in amountText = price.formattedForServer }
    }

    // MARK: Отметка

    @ViewBuilder
    private var attendanceControl: some View {
        if let status = student.attendanceStatus, !isChangingAttendance {
            // Выбранная отметка съедает вторую кнопку: место под ней нужнее
            // деньгам, а перепутать статус, когда он один на строке, невозможно.
            Button {
                withAnimation(.snappy(duration: 0.22)) { isChangingAttendance = true }
            } label: {
                Label(
                    status == .present ? "Был" : "Не был",
                    systemImage: status == .present ? "checkmark" : "xmark"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(status == .present ? Palette.prepaid : Palette.debt)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Нажмите, чтобы переставить отметку")
        } else {
            HStack(spacing: Spacing.s) {
                attendanceButton(
                    title: "Был", systemImage: "checkmark",
                    tint: Palette.prepaid, action: onMarkPresent
                )
                attendanceButton(
                    title: "Не был", systemImage: "xmark",
                    tint: Palette.debt, action: onMarkAbsent
                )
            }
        }
    }

    private func attendanceButton(
        title: String, systemImage: String, tint: Color, action: @escaping () async -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { isChangingAttendance = false }
            Task { await action() }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
                .foregroundStyle(tint)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Деньги

    @ViewBuilder
    private var paymentControl: some View {
        if let payment = student.payment {
            // Оплата принята — выбранный способ так же съел второй.
            HStack(spacing: Spacing.s) {
                Image(systemName: payment.isBalance ? "wallet.bifold" : "checkmark.circle.fill")
                Text(payment.amount.formatted(currency: currency))
                    .font(.tabular(.subheadline, weight: .semibold))
                Text(payment.methodDisplay.lowercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: Spacing.s)

                Button {
                    Task { await onResetPayment() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сбросить оплату")
            }
            .foregroundStyle(Palette.prepaid)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(
                Palette.prepaid.opacity(0.1),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
        } else if lessonPrice.isPositive {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    amountField
                    methodButton(cashLabel, systemImage: "banknote", method: .cash, tint: Palette.prepaid)
                    methodButton(transferLabel, systemImage: "creditcard", method: .transfer, tint: Palette.brand)
                }

                if let overpayment {
                    Text("Переплата \(overpayment.formatted(currency: currency)) уйдёт на предоплату.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Бесплатно")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Сумма уже подставлена ценой занятия: обычно её не трогают, но у половины
    /// учеников своя цена и скидки, и переписать число должно быть можно на месте.
    private var amountField: some View {
        HStack(spacing: 2) {
            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .font(.tabular(.subheadline, weight: .semibold))
                .frame(minWidth: 44)
            Text(currency)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.s)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(isAmountFocused ? Palette.brand : .clear, lineWidth: 2)
        }
        .frame(width: 108)
    }

    private func methodButton(
        _ title: String, systemImage: String, method: PaymentMethod, tint: Color
    ) -> some View {
        Button {
            guard let amount, amount.isPositive else { return }
            isAmountFocused = false
            Task { await onPay(amount, method) }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(amount?.isPositive != true)
    }
}

// MARK: - Отмена занятия

private struct CancelLessonSheet: View {
    let reasons: [MetaChoice]
    let onSubmit: (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var note = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Причина") {
                    Picker("Причина", selection: $reason) {
                        Text("Не указана").tag("")
                        ForEach(reasons) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Комментарий") {
                    TextField("Необязательно", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Text("Оплаты по занятию вернутся на баланс учеников.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Отмена занятия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отменить занятие") { submit() }
                }
            }
            .busy(isBusy)
        }
    }

    private func submit() {
        isBusy = true
        Task {
            await onSubmit(reason, note.trimmingCharacters(in: .whitespacesAndNewlines))
            isBusy = false
            dismiss()
        }
    }
}
