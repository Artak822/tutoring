import SwiftUI
import TutoringCore

/// Создание и правка ученика. Как и у занятия — одна форма на оба случая.
struct StudentFormScreen: View {
    enum Mode: Identifiable {
        case create
        case edit(Student)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let student): "edit-\(student.id)"
            }
        }

        var title: String {
            switch self {
            case .create: "Новый ученик"
            case .edit: "Ученик"
            }
        }
    }

    let mode: Mode
    let onSaved: () async -> Void

    @Environment(Session.self) private var session
    @Environment(GroupsStore.self) private var groupsStore
    @Environment(\.dismiss) private var dismiss

    @State private var groupIds: Set<Int> = []
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var telegram = ""
    @State private var grade = ""
    @State private var priceText = ""
    @State private var notes = ""

    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var isLoaded = false

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && (priceText.isEmpty || price != nil)
    }

    private var price: Money? { Money(string: priceText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    TextField("Фамилия", text: $lastName)
                    TextField("Имя", text: $firstName)
                    TextField("Класс", text: $grade)
                }

                Section("Контакты") {
                    TextField("Телефон", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Телеграм", text: $telegram)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    HStack {
                        TextField("Не задана", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.tabular(.body))
                        Text(session.currency)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Цена по умолчанию")
                } footer: {
                    Text("Подставится в форму занятия, когда выбран только этот ученик.")
                }

                if !groupsStore.groups.isEmpty {
                    Section("Группы") {
                        ForEach(groupsStore.groups) { group in
                            Button {
                                if groupIds.contains(group.id) {
                                    groupIds.remove(group.id)
                                } else {
                                    groupIds.insert(group.id)
                                }
                            } label: {
                                HStack {
                                    Text(group.name)
                                    Spacer()
                                    if groupIds.contains(group.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Palette.brand)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Заметки") {
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
            .task {
                await groupsStore.loadIfNeeded()
                prepare()
            }
        }
    }

    private func prepare() {
        guard !isLoaded else { return }
        isLoaded = true

        guard case .edit(let student) = mode else { return }
        firstName = student.firstName
        lastName = student.lastName
        phone = student.phone ?? ""
        telegram = student.telegram ?? ""
        grade = student.grade ?? ""
        priceText = student.defaultPrice?.formattedForServer ?? ""
        notes = student.notes
        groupIds = Set(student.groups)
    }

    private func save() {
        errorMessage = nil
        isBusy = true

        let payload = StudentPayload(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: optional(phone),
            telegram: optional(telegram),
            grade: optional(grade),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultPrice: priceText.isEmpty ? nil : price,
            groups: groupIds.sorted()
        )

        Task {
            defer { isBusy = false }
            do {
                switch mode {
                case .create:
                    _ = try await session.api.createStudent(payload)
                case .edit(let student):
                    _ = try await session.api.updateStudent(student.id, payload)
                }
                await onSaved()
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Пустая строка на сервере — это null, а не "": иначе телефон «» попадёт в поиск.
    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
