import Charts
import SwiftUI
import TutoringCore

/// Вкладка «Отчёты»: сводка по кабинету и прибыль за период — то же, что
/// dashboard и profit_report в вебе, но одним экраном и с графиком.
///
/// Сводка и отчёт разнесены в вебе, а на телефоне их смотрят подряд: сначала
/// «сколько всего», потом «откуда». Лишний переход между ними только мешает.
struct ReportsScreen: View {
    /// Готовые периоды закрывают почти все вопросы «сколько я заработал».
    /// Произвольный диапазон оставлен для сверки с бухгалтерией за конкретный месяц.
    enum Period: String, CaseIterable, Identifiable {
        case week = "Неделя"
        case month = "Месяц"
        case quarter = "Квартал"
        case custom = "Свой"

        var id: String { rawValue }
    }

    @Environment(Session.self) private var session
    @Environment(OfflineCache.self) private var cache

    @State private var summary: DashboardSummary?
    @State private var summaryError: String?
    /// Заполнено, пока сводка поднята с диска и сеть её ещё не подтвердила.
    @State private var summaryCachedAt: Date?

    @State private var period: Period = .month
    @State private var customStart = CalendarDate.today(calendar: DateText.calendar).adding(days: -30, calendar: DateText.calendar)
    @State private var customEnd = CalendarDate.today(calendar: DateText.calendar)

    @State private var report: ProfitReport?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                summarySection

                Section("Период") {
                    Picker("Период", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if period == .custom {
                        DatePicker("С", selection: startBinding, displayedComponents: .date)
                        DatePicker("По", selection: endBinding, displayedComponents: .date)
                    }
                }

                if let report {
                    totals(report)
                    chart(report)
                    byMethod(report)
                    byStudent(report)
                } else if let loadError {
                    Section {
                        ErrorStateView(message: loadError) { Task { await load() } }
                    }
                } else if isLoading {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Отчёты")
            .task { await loadSummary() }
            .task(id: reloadKey) { await load() }
            .refreshable {
                await loadSummary()
                await load()
            }
        }
    }

    // MARK: Секции

    @ViewBuilder
    private var summarySection: some View {
        if let summary {
            Section {
                LabeledContent("Учеников") {
                    Text(String(summary.studentsCount))
                        .font(.tabular(.body, weight: .semibold))
                }
                tileRow(
                    title: "Прибыль",
                    week: summary.profitWeek.formatted(currency: session.currency),
                    month: summary.profitMonth.formatted(currency: session.currency),
                    total: summary.profitAllTime.formatted(currency: session.currency)
                )
                tileRow(
                    title: "Занятия",
                    week: String(summary.lessonsWeek),
                    month: String(summary.lessonsMonth),
                    total: String(summary.lessonsAllTime)
                )
            } header: {
                Text("Сводка")
            } footer: {
                if summaryError != nil, let summaryCachedAt {
                    Text("Нет связи. Данные от \(DateText.relative(summaryCachedAt))")
                } else {
                    Text("Неделя и месяц — последние 7 и 30 дней, а не календарные.")
                }
            }
        } else if let summaryError {
            Section("Сводка") {
                Label(summaryError, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.debt)
                Button("Повторить") { Task { await loadSummary() } }
            }
        } else {
            Section("Сводка") {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Три плитки «неделя / месяц / всего» — компактнее шести отдельных строк,
    /// и цифры стоят в колонках, а не тонут в подписях.
    private func tileRow(
        title: String, week: String, month: String, total: String, tint: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.sectionTitle)

            HStack(spacing: Spacing.s) {
                StatTile(caption: "Неделя", value: week, tint: tint)
                StatTile(caption: "Месяц", value: month, tint: tint, isHighlighted: true)
                StatTile(caption: "Всего", value: total, tint: tint)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func totals(_ report: ProfitReport) -> some View {
        Section {
            // Итог периода — главное число экрана, поэтому крупно и отдельно,
            // а не строкой наравне со средними.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Всего за период")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(report.totalProfit.formatted(currency: session.currency))
                    .font(.tabular(.largeTitle, weight: .bold))
                    .foregroundStyle(Palette.brand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, Spacing.xs)

            HStack(spacing: Spacing.s) {
                StatTile(caption: "Занятий", value: String(report.lessonsCount))
                StatTile(
                    caption: "За занятие",
                    value: report.avgPerLesson.formatted(currency: session.currency)
                )
                StatTile(
                    caption: "За день",
                    value: report.avgPerDay.formatted(currency: session.currency)
                )
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            Text("\(DateText.full(report.startDate)) — \(DateText.full(report.endDate))")
        } footer: {
            Text("В прибыль не входят списания с предоплаты: эти деньги уже посчитаны в день, когда их внесли.")
        }
    }

    @ViewBuilder
    private func chart(_ report: ProfitReport) -> some View {
        if report.profitByDay.isEmpty {
            Section("По дням") {
                Text("За период оплат не было")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("По дням") {
                Chart(report.profitByDay) { day in
                    BarMark(
                        x: .value("День", day.paymentDate.date(in: DateText.calendar), unit: .day),
                        y: .value("Прибыль", day.total.chartValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Palette.violetSoft, Palette.violetDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
                }
                // Домен задаём периодом отчёта, а не данными: иначе один день оплат
                // растягивается на всю ширину, и по графику не видно, что это один день.
                .chartXScale(domain: report.startDate.date(in: DateText.calendar)
                    ... report.endDate.adding(days: 1, calendar: DateText.calendar).date(in: DateText.calendar))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(DateText.locale))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Money(Decimal(amount)).formatted(currency: ""))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding(.vertical, Spacing.s)
            }
        }
    }

    @ViewBuilder
    private func byMethod(_ report: ProfitReport) -> some View {
        if !report.profitByMethod.isEmpty {
            Section("По способу оплаты") {
                ForEach(report.profitByMethod) { row in
                    LabeledContent(session.label(forPaymentMethod: row.paymentMethod)) {
                        Text(row.total.formatted(currency: session.currency))
                            .font(.tabular(.body))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func byStudent(_ report: ProfitReport) -> some View {
        if !report.profitByStudent.isEmpty {
            Section("По ученикам") {
                ForEach(report.profitByStudent) { row in
                    NavigationLink {
                        StudentDetailScreen(studentId: row.studentId)
                    } label: {
                        LabeledContent(row.fullName) {
                            Text(row.total.formatted(currency: session.currency))
                                .font(.tabular(.body))
                        }
                    }
                }
            }
        }
    }

    // MARK: Период

    /// Ключ перезагрузки: меняется вместе с любым краем диапазона.
    private var reloadKey: String {
        "\(period.rawValue)-\(range.start.serverValue)-\(range.end.serverValue)"
    }

    private var range: (start: CalendarDate, end: CalendarDate) {
        let today = CalendarDate.today(calendar: DateText.calendar)
        switch period {
        case .week: return (today.adding(days: -6, calendar: DateText.calendar), today)
        case .month: return (today.adding(days: -29, calendar: DateText.calendar), today)
        case .quarter: return (today.adding(days: -89, calendar: DateText.calendar), today)
        case .custom: return (customStart, customEnd)
        }
    }

    /// DatePicker работает с `Date`, а по сети ходят календарные даты без времени.
    private var startBinding: Binding<Date> {
        Binding(
            get: { customStart.date(in: DateText.calendar) },
            set: { customStart = CalendarDate(date: $0, calendar: DateText.calendar) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { customEnd.date(in: DateText.calendar) },
            set: { customEnd = CalendarDate(date: $0, calendar: DateText.calendar) }
        )
    }

    private func loadSummary() async {
        if summary == nil, let snapshot = cache.read(DashboardSummary.self, for: CacheKey.dashboard) {
            summary = snapshot.value
            summaryCachedAt = snapshot.updatedAt
        }

        do {
            let fresh = try await session.api.dashboard()
            summary = fresh
            cache.write(fresh, for: CacheKey.dashboard)
            summaryCachedAt = nil
            summaryError = nil
        } catch is CancellationError {
        } catch {
            summaryError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            report = try await session.api.profitReport(from: range.start, to: range.end)
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private extension Money {
    /// Charts считает в `Double`. Точность здесь не критична — это высота столбика,
    /// а не сумма в отчёте; сами суммы по-прежнему `Decimal`.
    var chartValue: Double { NSDecimalNumber(decimal: amount).doubleValue }
}
