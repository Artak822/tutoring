import Foundation

public struct Endpoint: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    public var path: String
    public var method: Method
    public var query: [String: String]
    public var body: (any Encodable & Sendable)?
    public var requiresAuth: Bool

    public init(
        path: String,
        method: Method = .get,
        query: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

// Пути собраны в одном месте, чтобы строки не разъезжались по фичам.
extension Endpoint {

    // MARK: Аутентификация

    public static func login(username: String, password: String) -> Endpoint {
        Endpoint(
            path: "auth/login/", method: .post,
            body: LoginRequest(username: username, password: password),
            requiresAuth: false
        )
    }

    public static func register(_ request: RegisterRequest) -> Endpoint {
        Endpoint(path: "auth/register/", method: .post, body: request, requiresAuth: false)
    }

    public static let logout = Endpoint(path: "auth/logout/", method: .post)

    // MARK: Профиль и сводка

    public static let me = Endpoint(path: "me/")
    public static let meta = Endpoint(path: "meta/")
    public static let dashboard = Endpoint(path: "dashboard/")

    public static func profitReport(from: CalendarDate, to: CalendarDate) -> Endpoint {
        Endpoint(path: "reports/profit/", query: [
            "start_date": from.serverValue,
            "end_date": to.serverValue,
        ])
    }

    // MARK: Ученики

    public static func students(
        isActive: Bool? = true, search: String? = nil, group: Int? = nil, pageSize: Int = 200
    ) -> Endpoint {
        var query = ["page_size": String(pageSize)]
        if let isActive { query["is_active"] = isActive ? "true" : "false" }
        if let search, !search.isEmpty { query["search"] = search }
        if let group { query["group"] = String(group) }
        return Endpoint(path: "students/", query: query)
    }

    public static func student(_ id: Int) -> Endpoint {
        Endpoint(path: "students/\(id)/")
    }

    public static func studentHistory(_ id: Int) -> Endpoint {
        Endpoint(path: "students/\(id)/history/")
    }

    public static func createStudent(_ payload: StudentPayload) -> Endpoint {
        Endpoint(path: "students/", method: .post, body: payload)
    }

    public static func updateStudent(_ id: Int, _ payload: StudentPayload) -> Endpoint {
        Endpoint(path: "students/\(id)/", method: .patch, body: payload)
    }

    public static func archiveStudent(_ id: Int) -> Endpoint {
        Endpoint(path: "students/\(id)/archive/", method: .post)
    }

    public static func restoreStudent(_ id: Int) -> Endpoint {
        Endpoint(path: "students/\(id)/restore/", method: .post)
    }

    public static func deleteStudent(_ id: Int) -> Endpoint {
        Endpoint(path: "students/\(id)/", method: .delete)
    }

    // MARK: Долги

    public static let debts = Endpoint(path: "students/debts/")

    public static func clearDebts(studentId: Int, method: PaymentMethod, date: CalendarDate, notes: String = "") -> Endpoint {
        Endpoint(
            path: "students/\(studentId)/clear-debts/", method: .post,
            body: ClearDebtsRequest(paymentMethod: method, paymentDate: date, notes: notes)
        )
    }

    // MARK: Занятия

    public static func lessons(
        from: CalendarDate? = nil, to: CalendarDate? = nil,
        student: Int? = nil, status: LessonStatus? = nil, pageSize: Int = 200
    ) -> Endpoint {
        var query = ["page_size": String(pageSize)]
        if let from { query["date_from"] = from.serverValue }
        if let to { query["date_to"] = to.serverValue }
        if let student { query["student"] = String(student) }
        if let status { query["status"] = status.rawValue }
        return Endpoint(path: "lessons/", query: query)
    }

    public static func calendarMonth(year: Int, month: Int) -> Endpoint {
        Endpoint(path: "lessons/calendar/", query: ["year": String(year), "month": String(month)])
    }

    public static func lesson(_ id: Int) -> Endpoint {
        Endpoint(path: "lessons/\(id)/")
    }

    public static func lessonState(_ id: Int) -> Endpoint {
        Endpoint(path: "lessons/\(id)/state/")
    }

    public static func createLesson(_ payload: LessonPayload) -> Endpoint {
        Endpoint(path: "lessons/", method: .post, body: payload)
    }

    public static func updateLesson(_ id: Int, _ payload: LessonPayload) -> Endpoint {
        Endpoint(path: "lessons/\(id)/", method: .patch, body: payload)
    }

    public static func deleteLesson(_ id: Int) -> Endpoint {
        Endpoint(path: "lessons/\(id)/", method: .delete)
    }

    public static func recurringLessons(_ payload: RecurringLessonPayload) -> Endpoint {
        Endpoint(path: "lessons/recurring/", method: .post, body: payload)
    }

    public static func quickAction(lessonId: Int, _ action: QuickAction) -> Endpoint {
        Endpoint(path: "lessons/\(lessonId)/quick-action/", method: .post, body: action)
    }

    public static func cancelLesson(_ id: Int, reason: String, note: String) -> Endpoint {
        Endpoint(
            path: "lessons/\(id)/cancel/", method: .post,
            body: CancelLessonRequest(reason: reason, note: note)
        )
    }

    public static func restoreLesson(_ id: Int) -> Endpoint {
        Endpoint(path: "lessons/\(id)/restore/", method: .post)
    }

    // MARK: Группы

    public static func groups(pageSize: Int = 200) -> Endpoint {
        Endpoint(path: "groups/", query: ["page_size": String(pageSize)])
    }

    public static func createGroup(_ payload: GroupPayload) -> Endpoint {
        Endpoint(path: "groups/", method: .post, body: payload)
    }

    public static func updateGroup(_ id: Int, _ payload: GroupPayload) -> Endpoint {
        Endpoint(path: "groups/\(id)/", method: .patch, body: payload)
    }

    public static func deleteGroup(_ id: Int) -> Endpoint {
        Endpoint(path: "groups/\(id)/", method: .delete)
    }
}

// MARK: - Тела запросов

public struct LoginRequest: Encodable, Sendable {
    public let username: String
    public let password: String
}

public struct RegisterRequest: Encodable, Sendable {
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let phone: String
    public let password1: String
    public let password2: String

    public init(
        username: String, email: String, firstName: String,
        lastName: String, phone: String, password1: String, password2: String
    ) {
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.password1 = password1
        self.password2 = password2
    }
}

/// Действие быстрого закрытия занятия. Совпадает с QuickActionSerializer на сервере.
public struct QuickAction: Encodable, Sendable {
    public enum Kind: String, Encodable, Sendable {
        case markPresent = "mark_present"
        case markAbsent = "mark_absent"
        case addPayment = "add_payment"
        case resetPayment = "reset_payment"
    }

    public let action: Kind
    public let student: Int
    public let amount: String?
    public let method: PaymentMethod?

    public static func markPresent(student: Int) -> QuickAction {
        QuickAction(action: .markPresent, student: student, amount: nil, method: nil)
    }

    public static func markAbsent(student: Int) -> QuickAction {
        QuickAction(action: .markAbsent, student: student, amount: nil, method: nil)
    }

    public static func addPayment(student: Int, amount: Money, method: PaymentMethod) -> QuickAction {
        QuickAction(
            action: .addPayment, student: student,
            amount: amount.formattedForServer, method: method
        )
    }

    public static func resetPayment(student: Int) -> QuickAction {
        QuickAction(action: .resetPayment, student: student, amount: nil, method: nil)
    }
}

public struct CancelLessonRequest: Encodable, Sendable {
    public let reason: String
    public let note: String
}

public struct ClearDebtsRequest: Encodable, Sendable {
    public let paymentMethod: PaymentMethod
    public let paymentDate: CalendarDate
    public let notes: String
}

public struct StudentPayload: Encodable, Sendable {
    public var firstName: String
    public var lastName: String
    public var phone: String?
    public var telegram: String?
    public var grade: String?
    public var notes: String
    public var defaultPrice: Money?
    public var groups: [Int]

    public init(
        firstName: String, lastName: String, phone: String? = nil, telegram: String? = nil,
        grade: String? = nil, notes: String = "", defaultPrice: Money? = nil, groups: [Int] = []
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.telegram = telegram
        self.grade = grade
        self.notes = notes
        self.defaultPrice = defaultPrice
        self.groups = groups
    }
}

public struct LessonPayload: Encodable, Sendable {
    public var students: [Int]
    public var date: CalendarDate
    public var time: DayTime
    public var duration: Int
    public var lessonPrice: Money
    public var subject: String
    public var notes: String

    public init(
        students: [Int], date: CalendarDate, time: DayTime, duration: Int,
        lessonPrice: Money, subject: String = "", notes: String = ""
    ) {
        self.students = students
        self.date = date
        self.time = time
        self.duration = duration
        self.lessonPrice = lessonPrice
        self.subject = subject
        self.notes = notes
    }
}

public struct RecurringLessonPayload: Encodable, Sendable {
    public var students: [Int]
    public var startDate: CalendarDate
    public var time: DayTime
    public var duration: Int
    public var lessonPrice: Money
    public var period: String
    public var notes: String

    public init(
        students: [Int], startDate: CalendarDate, time: DayTime, duration: Int,
        lessonPrice: Money, period: String, notes: String = ""
    ) {
        self.students = students
        self.startDate = startDate
        self.time = time
        self.duration = duration
        self.lessonPrice = lessonPrice
        self.period = period
        self.notes = notes
    }
}

public struct GroupPayload: Encodable, Sendable {
    /// Пустое имя допустимо: сервер соберёт его из имён учеников.
    public var name: String
    public var description: String
    public var isActive: Bool
    public var students: [Int]

    public init(name: String, description: String = "", isActive: Bool = true, students: [Int] = []) {
        self.name = name
        self.description = description
        self.isActive = isActive
        self.students = students
    }
}
