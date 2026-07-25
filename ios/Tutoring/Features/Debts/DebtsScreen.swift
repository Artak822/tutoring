import SwiftUI
import TutoringCore

/// Должники по убыванию суммы и общий итог — то же, что `students_debt_list` в вебе.
///
/// Своей вкладки у долгов нет: они видны бейджем прямо в списке учеников,
/// а отдельный экран нужен только чтобы собрать их вместе и обзвонить.
struct DebtsScreen: View {
    @Environment(Session.self) private var session
    @Environment(StudentsStore.self) private var studentsStore
    @Environment(OfflineCache.self) private var cache

    @State private var debts: DebtList?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var clearTarget: Student?
    /// Заполнено, пока список поднят с диска и сеть его ещё не подтвердила.
    @State private var cachedAt: Date?

    var body: some View {
        Group {
            if let debts, !debts.students.isEmpty {
                list(debts)
            } else if let loadError {
                ErrorStateView(message: loadError) { Task { await load() } }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    title: "Долгов нет",
                    message: "Все отмеченные занятия оплачены.",
                    systemImage: "checkmark.seal"
                )
            }
        }
        .navigationTitle("Долги")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $clearTarget) { student in
            ClearDebtsSheet(student: student) {
                await studentsStore.refreshQuietly()
                await load(silently: true)
            }
        }
        .task { await load() }
        .refreshable { await load(silently: true) }
    }

    private func list(_ debts: DebtList) -> some View {
        List {
            if loadError != nil, let cachedAt {
                OfflineNoticeView(updatedAt: cachedAt)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(debts.students) { debt in
                    // Ссылка с готовым экраном, а не через `navigationDestination(for:)`:
                    // этот список сам открыт destination-ссылкой из «Учеников», и
                    // объявленный здесь маршрут стек уже не видит — строка нажимается,
                    // но ничего не происходит.
                    NavigationLink {
                        StudentDetailScreen(studentId: debt.id)
                    } label: {
                        DebtRow(debt: debt, currency: session.currency)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Погасить") { prepareClear(debt) }
                            .tint(Palette.prepaid)
                    }
                }
            } header: {
                HStack {
                    Text(plural(debts.students.count, "должник", "должника", "должников"))
                        .font(.sectionTitle)
                    Spacer()
                    Text(debts.totalDebt.formatted(currency: session.currency))
                        .font(.tabular(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.debt)
                }
                .textCase(nil)
            } footer: {
                Text("Долг считается по занятиям, где ученик отмечен как присутствовавший, но оплаты нет.")
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Лист погашения работает со `Student`, а список долгов отдаёт урезанную строку.
    /// Полную карточку берём из общего хранилища, оно уже загружено вкладкой «Ученики».
    private func prepareClear(_ debt: StudentDebt) {
        Task {
            if let student = studentsStore.student(debt.id) {
                clearTarget = student
            } else {
                await studentsStore.loadIfNeeded()
                clearTarget = studentsStore.student(debt.id)
            }
        }
    }

    private func load(silently: Bool = false) async {
        if !silently { isLoading = true }
        defer { isLoading = false }

        if debts == nil, let snapshot = cache.read(DebtList.self, for: CacheKey.debts) {
            debts = snapshot.value
            cachedAt = snapshot.updatedAt
        }

        do {
            let fresh = try await session.api.debts()
            debts = fresh
            cache.write(fresh, for: CacheKey.debts)
            cachedAt = nil
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct DebtRow: View {
    let debt: StudentDebt
    let currency: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            // Аватар в красном, а не в фирменном: на этом экране все строки —
            // должники, и цвет сразу говорит, зачем сюда зашли.
            StudentAvatar(name: debt.fullName, tint: Palette.debt)

            VStack(alignment: .leading, spacing: 2) {
                Text(debt.fullName)
                    .font(.body.weight(.medium))
                if let phone = debt.phone, !phone.isEmpty {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(debt.debt.formatted(currency: currency))
                    .font(.tabular(.body, weight: .semibold))
                    .foregroundStyle(Palette.debt)
                if debt.prepaidBalance.isPositive {
                    Text("на балансе \(debt.prepaidBalance.formatted(currency: currency))")
                        .font(.caption2)
                        .foregroundStyle(Palette.prepaid)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
