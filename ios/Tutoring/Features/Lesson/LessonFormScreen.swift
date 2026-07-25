import SwiftUI
import TutoringCore

/// Создание и правка занятия. Одна форма на оба случая: поля совпадают,
/// различается только запрос при сохранении.
struct LessonFormScreen: View {
    enum Mode: Identifiable {
        case create(date: CalendarDate)
        case edit(Lesson)

        var id: String {
            switch self {
            case .create(let date): "create-\(date.serverValue)"
            case .edit(let lesson): "edit-\(lesson.id)"
            }
        }

        var title: String {
            switch self {
            case .create: "Новое занятие"
            case .edit: "Занятие"
            }
        }
    }

    let mode: Mode
    let onSaved: () async -> Void

    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var studentsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStudents: Set<Int> = []
    @State private var date = CalendarDate.today(calendar: DateText.calendar)
    @State private var time = DayTime(hour: 15, minute: 0)
    @State private var duration = 60
    @State private var priceText = ""
    @State private var subject = ""
    @State private var notes = ""

    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var isLoaded = false

    private var price: Money? { Money(string: priceText.replacingOccurrences(of: ",", with: ".")) }

    private var canSave: Bool {
        !selectedStudents.isEmpty && price != nil && duration > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ученики") {
                    StudentPicker(selection: $selectedStudents)
                }

                Section("Когда") {
                    DatePicker(
                        "Дата",
                        selection: Binding(
                            get: { date.date(in: DateText.calendar) },
                            set: { date = CalendarDate(date: $0, calendar: DateText.calendar) }
                        ),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "Время",
                        selection: Binding(
                            get: { date.combined(with: time, calendar: DateText.calendar) },
                            set: {
                                let parts = DateText.calendar.dateComponents([.hour, .minute], from: $0)
                                time = DayTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    Picker("Длительность", selection: $duration) {
                        ForEach([30, 45, 60, 90, 120], id: \.self) { minutes in
                            Text(DateText.duration(minutes)).tag(minutes)
                        }
                    }
                }

                Section("Стоимость") {
                    HStack {
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.tabular(.body))
                        Text(session.currency)
                            .foregroundStyle(.secondary)
                    }
                    if selectedStudents.count > 1, let price {
                        LabeledContent("Итого за занятие") {
                            Text(total(price).formatted(currency: session.currency))
                                .font(.tabular(.body, weight: .semibold))
                        }
                    }
                }

                Section("Дополнительно") {
                    TextField("Предмет", text: $subject)
                    TextField("Заметки", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Palette.debt)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(!canSave)
                }
            }
            .busy(isBusy)
            .task { prepare() }
            .onChange(of: selectedStudents) { _, students in
                suggestPrice(for: students)
            }
        }
    }

    /// Подставляем цену из карточки ученика — так же, как это делает веб-форма.
    /// Уже введённую цену не трогаем.
    private func suggestPrice(for students: Set<Int>) {
        guard priceText.isEmpty, students.count == 1, let id = students.first,
              let defaultPrice = studentsStore.student(id)?.defaultPrice else { return }
        priceText = defaultPrice.formattedForServer
    }

    /// Стоимость в модели — цена за одного ученика, итог по занятию считает сервер.
    private func total(_ price: Money) -> Money {
        (0..<selectedStudents.count).reduce(Money.zero) { sum, _ in sum + price }
    }

    private func prepare() {
        guard !isLoaded else { return }
        isLoaded = true

        switch mode {
        case .create(let day):
            date = day
            // Цена по умолчанию — из карточки ученика, как делает веб-форма
            priceText = ""
        case .edit(let lesson):
            selectedStudents = Set(lesson.students)
            date = lesson.date
            time = lesson.time
            duration = lesson.duration
            priceText = lesson.lessonPrice.formattedForServer
            subject = lesson.subject
            notes = lesson.notes
        }
    }

    private func save() {
        guard let price, !selectedStudents.isEmpty else { return }
        errorMessage = nil
        isBusy = true

        let payload = LessonPayload(
            students: Array(selectedStudents).sorted(),
            date: date,
            time: time,
            duration: duration,
            lessonPrice: price,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        Task {
            defer { isBusy = false }
            do {
                switch mode {
                case .create:
                    _ = try await session.api.createLesson(payload)
                case .edit(let lesson):
                    _ = try await session.api.updateLesson(lesson.id, payload)
                }
                await onSaved()
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Выбор учеников с поиском — общий для формы занятия и серии занятий.
struct StudentPicker: View {
    @Binding var selection: Set<Int>
    @Environment(StudentsStore.self) private var store
    @State private var search = ""

    private var filtered: [Student] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return store.students }
        return store.students.filter { $0.fullName.lowercased().contains(term) }
    }

    var body: some View {
        if store.students.isEmpty {
            Text("Сначала добавьте учеников")
                .foregroundStyle(.secondary)
        } else {
            if store.students.count > 8 {
                TextField("Поиск", text: $search)
                    .textInputAutocapitalization(.never)
            }
            ForEach(filtered) { student in
                Button {
                    if selection.contains(student.id) {
                        selection.remove(student.id)
                    } else {
                        selection.insert(student.id)
                    }
                } label: {
                    HStack {
                        Text(student.fullName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.brand)
                        }
                    }
                }
            }
        }
    }
}
