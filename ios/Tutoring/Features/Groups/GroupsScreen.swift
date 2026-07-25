import SwiftUI
import TutoringCore

/// Группы учеников: список, создание, правка состава.
struct GroupsScreen: View {
    @Environment(GroupsStore.self) private var store
    @Environment(StudentsStore.self) private var studentsStore

    @State private var form: GroupFormScreen.Mode?

    var body: some View {
        Group {
            if store.groups.isEmpty, store.hasLoaded {
                EmptyStateView(
                    title: "Групп пока нет",
                    message: "Группа собирает учеников, которые ходят вместе.",
                    systemImage: "person.3",
                    actionTitle: "Создать группу",
                    action: { form = .create }
                )
            } else if let error = store.errorMessage, store.groups.isEmpty {
                ErrorStateView(message: error) { Task { await store.load() } }
            } else {
                list
            }
        }
        .navigationTitle("Группы")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { form = .create } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $form) { mode in
            GroupFormScreen(mode: mode) { await store.load() }
        }
        .task {
            await store.loadIfNeeded()
            await studentsStore.loadIfNeeded()
        }
        .refreshable { await store.load() }
    }

    private var list: some View {
        List {
            if let cachedAt = store.offlineSince {
                OfflineNoticeView(updatedAt: cachedAt)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(store.groups) { group in
                // Ссылка с готовым экраном, а не с value: сам список открыт из «Ещё»
                // тем же способом, и второй `navigationDestination` в одном стеке
                // SwiftUI игнорирует — переход по строке просто не срабатывал.
                NavigationLink {
                    GroupDetailScreen(groupId: group.id)
                } label: {
                    GroupRow(group: group)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct GroupRow: View {
    let group: StudentGroup

    var body: some View {
        HStack(spacing: Spacing.m) {
            // Кружок вместо инициалов: у группы нет имени, из которого их взять,
            // но пустое место слева ломало бы ритм списка учеников рядом.
            Circle()
                .fill(Palette.brandSurface)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.brand)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body.weight(.medium))
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.s)

            if !group.isActive {
                Badge(text: "Не активна", tint: Palette.muted)
            }
            Text(plural(group.studentsCount, "ученик", "ученика", "учеников"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Карточка группы: состав и занятия, где эта группа собирается целиком.
struct GroupDetailScreen: View {
    let groupId: Int

    @Environment(GroupsStore.self) private var store
    @Environment(StudentsStore.self) private var studentsStore
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingEdit = false
    @State private var isConfirmingDelete = false
    @State private var actionError: String?

    private var group: StudentGroup? { store.group(groupId) }

    /// Архивных в списке нет — показываем тех, кого действительно можно позвать на занятие.
    private var members: [Student] {
        guard let group else { return [] }
        return studentsStore.students
            .filter { group.students.contains($0.id) }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    var body: some View {
        Group {
            if let group {
                content(group)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(group?.name ?? "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if group != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Изменить", systemImage: "pencil") { isShowingEdit = true }
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Действия с группой")
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            if let group {
                GroupFormScreen(mode: .edit(group)) { await store.load() }
            }
        }
        .alert("Удалить группу?", isPresented: $isConfirmingDelete) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { delete() }
        } message: {
            Text("Ученики останутся на месте — пропадёт только объединение.")
        }
        .task {
            await store.loadIfNeeded()
            await studentsStore.loadIfNeeded()
        }
    }

    private func content(_ group: StudentGroup) -> some View {
        List {
            if !group.description.isEmpty {
                Section("Описание") {
                    Text(group.description)
                }
            }

            Section {
                if members.isEmpty {
                    Text("В группе пока никого")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(members) { student in
                        NavigationLink {
                            StudentDetailScreen(studentId: student.id)
                        } label: {
                            HStack(spacing: Spacing.m) {
                                StudentAvatar(name: student.fullName, size: 32)
                                Text(student.fullName)
                                Spacer()
                                if let grade = student.grade, !grade.isEmpty {
                                    Text(grade)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Состав")
            } footer: {
                if group.students.count > members.count {
                    Text("Ещё \(group.students.count - members.count) из архива не показаны.")
                }
            }

            if !group.isActive {
                Section {
                    Label("Группа не активна", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let actionError {
                Section {
                    Label(actionError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Palette.debt)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func delete() {
        Task {
            do {
                try await session.api.deleteGroup(groupId)
                await store.load()
                // Ученики держат список групп у себя — после удаления он протух
                await studentsStore.refreshQuietly()
                dismiss()
            } catch {
                actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
