import SwiftUI
import TutoringCore

/// Серия еженедельных занятий. Периоды берём из `meta/`, чтобы список
/// не разъезжался с сервером.
struct RecurringLessonScreen: View {
    let startDate: CalendarDate
    let onSaved: () async -> Void

    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var studentsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStudents: Set<Int> = []
    @State private var date = CalendarDate.today(calendar: DateText.calendar)
    @State private var time = DayTime(hour: 15, minute: 0)
    @State private var duration = 60
    @State private var priceText = ""
    @State private var period = "1month"
    @State private var notes = ""

    @State private var errorMessage: String?
    @State private var createdCount: Int?
    @State private var isBusy = false
    @State private var isLoaded = false

    private var price: Money? { Money(string: priceText.replacingOccurrences(of: ",", with: ".")) }
    private var canSave: Bool { !selectedStudents.isEmpty && price != nil }

    private var periods: [MetaChoice] {
        session.meta?.recurringPeriods ?? [MetaChoice(value: "1month", label: "1 месяц")]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ученики") {
                    StudentPicker(selection: $selectedStudents)
                }

                Section {
                    DatePicker(
                        "Первое занятие",
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
                    Picker("Повторять", selection: $period) {
                        ForEach(periods) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                } header: {
                    Text("Расписание")
                } footer: {
                    Text("Занятия создаются каждую неделю в тот же день и час.")
                }

                Section("Стоимость") {
                    HStack {
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.tabular(.body))
                        Text(session.currency)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Дополнительно") {
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
            .navigationTitle("Серия занятий")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать", action: save)
                        .disabled(!canSave)
                }
            }
            .busy(isBusy)
            .task {
                guard !isLoaded else { return }
                isLoaded = true
                date = startDate
            }
            .onChange(of: selectedStudents) { _, students in
                guard priceText.isEmpty, students.count == 1, let id = students.first,
                      let defaultPrice = studentsStore.student(id)?.defaultPrice else { return }
                priceText = defaultPrice.formattedForServer
            }
            .alert("Готово", isPresented: Binding(
                get: { createdCount != nil },
                set: { if !$0 { createdCount = nil } }
            )) {
                Button("Отлично") { dismiss() }
            } message: {
                Text("Создано \(plural(createdCount ?? 0, "занятие", "занятия", "занятий"))")
            }
        }
    }

    private func save() {
        guard let price, !selectedStudents.isEmpty else { return }
        errorMessage = nil
        isBusy = true

        let payload = RecurringLessonPayload(
            students: Array(selectedStudents).sorted(),
            startDate: date,
            time: time,
            duration: duration,
            lessonPrice: price,
            period: period,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        Task {
            defer { isBusy = false }
            do {
                let result = try await session.api.createRecurringLessons(payload)
                await onSaved()
                createdCount = result.createdCount
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
