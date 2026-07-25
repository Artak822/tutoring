import Foundation

/// Типизированный фасад над `APIClient`. Экраны работают только с ним и не собирают
/// пути руками.
public protocol TutoringAPIProtocol: Sendable {
    func login(username: String, password: String) async throws -> String
    func register(_ request: RegisterRequest) async throws -> String
    func logout() async throws
    func me() async throws -> Tutor
    func meta() async throws -> APIMeta
    func dashboard() async throws -> DashboardSummary
    func profitReport(from: CalendarDate, to: CalendarDate) async throws -> ProfitReport

    func students(isActive: Bool?, search: String?, group: Int?) async throws -> [Student]
    func student(_ id: Int) async throws -> Student
    func studentHistory(_ id: Int) async throws -> StudentHistory
    func createStudent(_ payload: StudentPayload) async throws -> Student
    func updateStudent(_ id: Int, _ payload: StudentPayload) async throws -> Student
    func archiveStudent(_ id: Int) async throws
    func restoreStudent(_ id: Int) async throws
    func deleteStudent(_ id: Int) async throws
    func debts() async throws -> DebtList
    func clearDebts(studentId: Int, method: PaymentMethod, date: CalendarDate, notes: String) async throws -> ClearDebtsResult

    func calendarMonth(year: Int, month: Int) async throws -> CalendarMonth
    func lessons(from: CalendarDate?, to: CalendarDate?, student: Int?, status: LessonStatus?) async throws -> [Lesson]
    func lesson(_ id: Int) async throws -> Lesson
    func lessonState(_ id: Int) async throws -> LessonState
    func createLesson(_ payload: LessonPayload) async throws -> Lesson
    func updateLesson(_ id: Int, _ payload: LessonPayload) async throws -> Lesson
    func deleteLesson(_ id: Int) async throws
    func createRecurringLessons(_ payload: RecurringLessonPayload) async throws -> RecurringLessonsResult
    func quickAction(lessonId: Int, _ action: QuickAction) async throws -> QuickActionResult
    func cancelLesson(_ id: Int, reason: String, note: String) async throws -> LessonStatusChange
    func restoreLesson(_ id: Int) async throws -> LessonStatusChange

    func groups() async throws -> [StudentGroup]
    func createGroup(_ payload: GroupPayload) async throws -> StudentGroup
    func updateGroup(_ id: Int, _ payload: GroupPayload) async throws -> StudentGroup
    func deleteGroup(_ id: Int) async throws
}

public struct TutoringAPI: TutoringAPIProtocol {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: Аутентификация

    public func login(username: String, password: String) async throws -> String {
        let auth: AuthToken = try await client.send(.login(username: username, password: password))
        await client.storeToken(auth.token)
        return auth.token
    }

    public func register(_ request: RegisterRequest) async throws -> String {
        let auth: AuthToken = try await client.send(.register(request))
        await client.storeToken(auth.token)
        return auth.token
    }

    public func logout() async throws {
        // Токен чистим в любом случае: локальный выход не должен зависеть от сети.
        defer { Task { await client.clearToken() } }
        try await client.sendIgnoringResponse(.logout)
    }

    public func me() async throws -> Tutor {
        try await client.send(.me)
    }

    public func meta() async throws -> APIMeta {
        try await client.send(.meta)
    }

    public func dashboard() async throws -> DashboardSummary {
        try await client.send(.dashboard)
    }

    public func profitReport(from: CalendarDate, to: CalendarDate) async throws -> ProfitReport {
        try await client.send(.profitReport(from: from, to: to))
    }

    // MARK: Ученики

    public func students(
        isActive: Bool? = true, search: String? = nil, group: Int? = nil
    ) async throws -> [Student] {
        let page: Page<Student> = try await client.send(
            .students(isActive: isActive, search: search, group: group)
        )
        return page.results
    }

    public func student(_ id: Int) async throws -> Student {
        try await client.send(.student(id))
    }

    public func studentHistory(_ id: Int) async throws -> StudentHistory {
        try await client.send(.studentHistory(id))
    }

    public func createStudent(_ payload: StudentPayload) async throws -> Student {
        try await client.send(.createStudent(payload))
    }

    public func updateStudent(_ id: Int, _ payload: StudentPayload) async throws -> Student {
        try await client.send(.updateStudent(id, payload))
    }

    public func archiveStudent(_ id: Int) async throws {
        try await client.sendIgnoringResponse(.archiveStudent(id))
    }

    public func restoreStudent(_ id: Int) async throws {
        try await client.sendIgnoringResponse(.restoreStudent(id))
    }

    public func deleteStudent(_ id: Int) async throws {
        try await client.sendIgnoringResponse(.deleteStudent(id))
    }

    public func debts() async throws -> DebtList {
        try await client.send(.debts)
    }

    public func clearDebts(
        studentId: Int, method: PaymentMethod, date: CalendarDate, notes: String = ""
    ) async throws -> ClearDebtsResult {
        try await client.send(.clearDebts(studentId: studentId, method: method, date: date, notes: notes))
    }

    // MARK: Занятия

    public func calendarMonth(year: Int, month: Int) async throws -> CalendarMonth {
        try await client.send(.calendarMonth(year: year, month: month))
    }

    public func lessons(
        from: CalendarDate? = nil, to: CalendarDate? = nil,
        student: Int? = nil, status: LessonStatus? = nil
    ) async throws -> [Lesson] {
        let page: Page<Lesson> = try await client.send(
            .lessons(from: from, to: to, student: student, status: status)
        )
        return page.results
    }

    public func lesson(_ id: Int) async throws -> Lesson {
        try await client.send(.lesson(id))
    }

    public func lessonState(_ id: Int) async throws -> LessonState {
        try await client.send(.lessonState(id))
    }

    public func createLesson(_ payload: LessonPayload) async throws -> Lesson {
        try await client.send(.createLesson(payload))
    }

    public func updateLesson(_ id: Int, _ payload: LessonPayload) async throws -> Lesson {
        try await client.send(.updateLesson(id, payload))
    }

    public func deleteLesson(_ id: Int) async throws {
        try await client.sendIgnoringResponse(.deleteLesson(id))
    }

    public func createRecurringLessons(_ payload: RecurringLessonPayload) async throws -> RecurringLessonsResult {
        try await client.send(.recurringLessons(payload))
    }

    public func quickAction(lessonId: Int, _ action: QuickAction) async throws -> QuickActionResult {
        try await client.send(.quickAction(lessonId: lessonId, action))
    }

    public func cancelLesson(_ id: Int, reason: String, note: String) async throws -> LessonStatusChange {
        try await client.send(.cancelLesson(id, reason: reason, note: note))
    }

    public func restoreLesson(_ id: Int) async throws -> LessonStatusChange {
        try await client.send(.restoreLesson(id))
    }

    // MARK: Группы

    public func groups() async throws -> [StudentGroup] {
        let page: Page<StudentGroup> = try await client.send(.groups())
        return page.results
    }

    public func createGroup(_ payload: GroupPayload) async throws -> StudentGroup {
        try await client.send(.createGroup(payload))
    }

    public func updateGroup(_ id: Int, _ payload: GroupPayload) async throws -> StudentGroup {
        try await client.send(.updateGroup(id, payload))
    }

    public func deleteGroup(_ id: Int) async throws {
        try await client.sendIgnoringResponse(.deleteGroup(id))
    }
}
