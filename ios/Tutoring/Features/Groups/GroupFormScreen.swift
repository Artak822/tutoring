import SwiftUI
import TutoringCore

/// Создание и правка группы вместе с её составом.
struct GroupFormScreen: View {
    enum Mode: Identifiable {
        case create
        case edit(StudentGroup)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let group): "edit-\(group.id)"
            }
        }

        var title: String {
            switch self {
            case .create: "Новая группа"
            case .edit: "Группа"
            }
        }
    }

    let mode: Mode
    let onSaved: () async -> Void

    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var studentsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isActive = true
    @State private var selected: Set<Int> = []

    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var isLoaded = false

    private var students: [Student] {
        studentsStore.students.sorted {
            $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                } header: {
                    Text("Название")
                } footer: {
                    Text("Можно не заполнять — соберётся из имён учеников.")
                }

                Section("Описание") {
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    if students.isEmpty {
                        Text("Учеников пока нет")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(students) { student in
                            Button {
                                toggle(student.id)
                            } label: {
                                HStack {
                                    Text(student.fullName)
                                    Spacer()
                                    if selected.contains(student.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Palette.brand)
                                    }
                                }
                                // Иначе пустое место справа от имени не нажимается
                                .contentShape(.rect)
                            }
                            // Без этого кнопка красит всю строку в акцентный цвет
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Состав")
                } footer: {
                    Text("Выбрано: \(selected.count)")
                }

                Section {
                    Toggle("Активна", isOn: $isActive)
                } footer: {
                    Text("Неактивная группа остаётся в списке, но помечается серым.")
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
                }
            }
            .busy(isBusy)
            .task {
                await studentsStore.loadIfNeeded()
                prepare()
            }
        }
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func prepare() {
        guard !isLoaded else { return }
        isLoaded = true

        guard case .edit(let group) = mode else { return }
        name = group.name
        description = group.description
        isActive = group.isActive
        selected = Set(group.students)
    }

    private func save() {
        errorMessage = nil
        isBusy = true

        let payload = GroupPayload(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: isActive,
            // Порядок не важен серверу, но стабильный список удобнее сравнивать в логах
            students: selected.sorted()
        )

        Task {
            defer { isBusy = false }
            do {
                switch mode {
                case .create:
                    _ = try await session.api.createGroup(payload)
                case .edit(let group):
                    _ = try await session.api.updateGroup(group.id, payload)
                }
                await onSaved()
                // Списки групп у учеников меняются вместе с составом
                await studentsStore.refreshQuietly()
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
