import SwiftUI
import TutoringCore

/// Список активных учеников: поиск, бейдж долга или предоплаты, переход в карточку.
struct StudentsScreen: View {
    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var store

    @State private var search = ""
    @State private var form: StudentFormScreen.Mode?
    @State private var isShowingArchive = false

    private var filtered: [Student] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return store.students }
        return store.students.filter {
            $0.fullName.lowercased().contains(term)
                || ($0.phone ?? "").contains(term)
                || ($0.grade ?? "").lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let message = store.errorMessage, store.students.isEmpty {
                    ErrorStateView(message: message) { Task { await store.load() } }
                } else if store.students.isEmpty && store.hasLoaded {
                    EmptyStateView(
                        title: "Учеников пока нет",
                        message: "Добавьте первого ученика — и его можно будет ставить в занятия.",
                        systemImage: "person.2",
                        actionTitle: "Добавить ученика",
                        action: { form = .create }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Ученики")
            .searchable(text: $search, prompt: "Имя, телефон, класс")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Новый ученик", systemImage: "plus") { form = .create }
                        Button("Архив", systemImage: "archivebox") { isShowingArchive = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Student.self) { student in
                StudentDetailScreen(studentId: student.id)
            }
            .navigationDestination(isPresented: $isShowingArchive) {
                ArchiveScreen()
            }
            .sheet(item: $form) { mode in
                StudentFormScreen(mode: mode) { await store.load() }
            }
            .task { await store.loadIfNeeded() }
            .refreshable { await store.load() }
        }
    }

    private var list: some View {
        List {
            if let cachedAt = store.offlineSince {
                OfflineNoticeView(updatedAt: cachedAt)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            shortcuts

            if filtered.isEmpty {
                Text("Никого не нашлось")
                    .foregroundStyle(.secondary)
            }
            ForEach(filtered) { student in
                NavigationLink(value: student) {
                    StudentRow(student: student, currency: session.currency)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Долги и группы — про тех же учеников, поэтому живут здесь, а не отдельными
    /// вкладками: место на нижней панели дороже, а долг и так виден бейджем в строке.
    @ViewBuilder
    private var shortcuts: some View {
        if search.isEmpty {
            Section {
                NavigationLink {
                    DebtsScreen()
                } label: {
                    HStack(spacing: Spacing.m) {
                        ShortcutIcon(systemImage: "exclamationmark.circle.fill", tint: Palette.debt)
                        Text("Долги")
                        Spacer(minLength: Spacing.s)
                        if totalDebt.isPositive {
                            Text(totalDebt.formatted(currency: session.currency))
                                .font(.tabular(.subheadline, weight: .semibold))
                                .foregroundStyle(Palette.debt)
                        }
                    }
                }

                NavigationLink {
                    GroupsScreen()
                } label: {
                    HStack(spacing: Spacing.m) {
                        ShortcutIcon(systemImage: "person.3.fill", tint: Palette.brand)
                        Text("Группы")
                    }
                }
            }
        }
    }

    /// Считаем по уже загруженному списку: отдельный запрос ради строки-ссылки
    /// не нужен, а точная разбивка ждёт на самом экране долгов.
    private var totalDebt: Money {
        store.students.reduce(Money.zero) { sum, student in
            if case .debt(let amount) = student.balanceState { return sum + amount }
            return sum
        }
    }
}

/// Значок строки-ссылки в списке: цветной квадратик, как в системных настройках.
struct ShortcutIcon: View {
    let systemImage: String
    var tint: Color = Palette.brand

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint)
            .frame(width: 29, height: 29)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Кружок с инициалами вместо фотографии: фото в CRM никто не заводит,
/// а глазу нужна зацепка, чтобы не читать список построчно.
struct StudentAvatar: View {
    let name: String
    var size: CGFloat = 38
    var tint: Color = Palette.brand

    var body: some View {
        Circle()
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Строка списка учеников — имя, класс и денежный бейдж.
struct StudentRow: View {
    let student: Student
    let currency: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            StudentAvatar(name: student.fullName)

            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(.body.weight(.medium))
                if let grade = student.grade, !grade.isEmpty {
                    Text(grade)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: Spacing.s)

            switch student.balanceState {
            case .debt(let amount):
                Badge(
                    text: amount.formatted(currency: currency),
                    systemImage: "exclamationmark.circle",
                    tint: Palette.debt
                )
            case .prepaid(let amount):
                Badge(
                    text: amount.formatted(currency: currency),
                    systemImage: "wallet.bifold",
                    tint: Palette.prepaid
                )
            case .clear:
                EmptyView()
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Архив: восстановить или удалить окончательно.
struct ArchiveScreen: View {
    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var store

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingDelete: Student?

    var body: some View {
        Group {
            if isLoading && store.archived.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.archived.isEmpty {
                EmptyStateView(
                    title: "Архив пуст",
                    message: "Сюда попадают ученики, с которыми вы больше не занимаетесь.",
                    systemImage: "archivebox"
                )
            } else {
                List {
                    ForEach(store.archived) { student in
                        HStack {
                            StudentRow(student: student, currency: session.currency)
                            Button("Вернуть") { Task { await restore(student) } }
                                .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Удалить", role: .destructive) { pendingDelete = student }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Архив")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadArchived()
            isLoading = false
        }
        .alert("Удалить навсегда?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let student = pendingDelete { Task { await delete(student) } }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Занятия, оплаты и история этого ученика пропадут без возможности вернуть.")
        }
        .alert("Не получилось", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func restore(_ student: Student) async {
        do {
            try await session.api.restoreStudent(student.id)
            await store.loadArchived()
            await store.load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ student: Student) async {
        do {
            try await session.api.deleteStudent(student.id)
            await store.loadArchived()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
