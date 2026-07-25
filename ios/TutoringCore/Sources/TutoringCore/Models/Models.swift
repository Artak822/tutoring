import Foundation

// Модели повторяют main/serializers.py. Именование полей на сервере snake_case,
// декодер настроен на конвертацию, поэтому здесь camelCase без CodingKeys.

public struct Tutor: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let username: String
    public let firstName: String
    public let lastName: String
    public let phone: String?
    public let studentsCount: Int

    public var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? username : full
    }
}

public struct Student: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let groups: [Int]
    public let firstName: String
    public let lastName: String
    public let phone: String?
    public let telegram: String?
    public let grade: String?
    public let notes: String
    public let isActive: Bool
    public let defaultPrice: Money?
    public let prepaidBalance: Money
    public let totalPaid: Money
    public let totalDebt: Money

    public var fullName: String {
        "\(lastName) \(firstName)".trimmingCharacters(in: .whitespaces)
    }

    public var shortName: String {
        guard let initial = firstName.first else { return lastName }
        return "\(lastName) \(initial)."
    }

    /// Что показывать бейджем в списке — ровно как в вебе.
    public enum BalanceState: Sendable, Hashable {
        case debt(Money)
        case prepaid(Money)
        case clear
    }

    public var balanceState: BalanceState {
        if totalDebt.isPositive { return .debt(totalDebt) }
        if prepaidBalance.isPositive { return .prepaid(prepaidBalance) }
        return .clear
    }
}

public struct StudentGroup: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let isActive: Bool
    /// Состав группы. `studentsCount` считает только активных, поэтому расходится
    /// с длиной этого списка, если кого-то из группы отправили в архив.
    public let students: [Int]
    public let studentsCount: Int
}

public enum LessonStatus: String, Codable, Hashable, Sendable {
    case scheduled
    case cancelled
}

public struct Lesson: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let students: [Int]
    public let date: CalendarDate
    public let time: DayTime
    public let duration: Int
    public let lessonPrice: Money
    public let subject: String
    public let notes: String
    public let status: LessonStatus
    public let cancellationReason: String
    public let cancellationReasonDisplay: String?
    public let cancellationNote: String
    public let presentStudentsCount: Int
    public let totalPrice: Money

    // Автоматический memberwise-инициализатор у public-структуры остаётся internal,
    // а приложению он нужен: после cancel/restore сервер присылает только статус,
    // и занятие пересобирается на месте.
    public init(
        id: Int, students: [Int], date: CalendarDate, time: DayTime, duration: Int,
        lessonPrice: Money, subject: String, notes: String, status: LessonStatus,
        cancellationReason: String, cancellationReasonDisplay: String?, cancellationNote: String,
        presentStudentsCount: Int, totalPrice: Money
    ) {
        self.id = id
        self.students = students
        self.date = date
        self.time = time
        self.duration = duration
        self.lessonPrice = lessonPrice
        self.subject = subject
        self.notes = notes
        self.status = status
        self.cancellationReason = cancellationReason
        self.cancellationReasonDisplay = cancellationReasonDisplay
        self.cancellationNote = cancellationNote
        self.presentStudentsCount = presentStudentsCount
        self.totalPrice = totalPrice
    }

    public var isCancelled: Bool { status == .cancelled }

    /// Сколько занятие стоит по плану. `totalPrice` с сервера — это уже заработанное
    /// (цена × отмеченные), и до отметок оно равно нулю; в расписании нужна плановая сумма.
    public var plannedPrice: Money {
        (0..<max(students.count, 1)).reduce(Money.zero) { sum, _ in sum + lessonPrice }
    }

    public var startsAt: Date { date.combined(with: time) }
    public var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(duration * 60)) }
    public var isGroupLesson: Bool { students.count > 1 }
}

public enum AttendanceStatus: String, Codable, Hashable, Sendable {
    case present
    case absent
}

public enum PaymentMethod: String, Codable, Hashable, Sendable {
    case cash
    case transfer
    case balance
}

public struct Payment: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let student: Int
    public let lesson: Int?
    public let amount: Money
    public let paymentDate: CalendarDate
    public let paymentMethod: PaymentMethod
    public let notes: String
    public let isBalancePayment: Bool
}

public struct Attendance: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let lesson: Int
    public let student: Int
    public let status: AttendanceStatus
    public let notes: String
}

// MARK: - Быстрое закрытие занятия

/// Оплата в ответе quick-action и lesson state — это не модель Payment,
/// а компактная сводка, которую сервер собирает в services.payment_to_dict.
public struct PaymentSummary: Codable, Hashable, Sendable {
    public let amount: Money
    public let method: PaymentMethod
    public let methodDisplay: String
    public let isBalance: Bool
}

public struct QuickActionResult: Codable, Hashable, Sendable {
    public let attendanceStatus: AttendanceStatus?
    public let payment: PaymentSummary?
    public let studentBalance: Money
    public let lessonPrice: Money
}

public struct LessonStudentState: Codable, Hashable, Sendable, Identifiable {
    public let studentId: Int
    public let firstName: String
    public let lastName: String
    public let attendanceStatus: AttendanceStatus?
    public let payment: PaymentSummary?
    public let studentBalance: Money

    public init(
        studentId: Int, firstName: String, lastName: String,
        attendanceStatus: AttendanceStatus?, payment: PaymentSummary?, studentBalance: Money
    ) {
        self.studentId = studentId
        self.firstName = firstName
        self.lastName = lastName
        self.attendanceStatus = attendanceStatus
        self.payment = payment
        self.studentBalance = studentBalance
    }

    public var id: Int { studentId }
    public var fullName: String { "\(lastName) \(firstName)".trimmingCharacters(in: .whitespaces) }

    /// Ученик отмечен, но занятие не оплачено — это и есть будущий долг.
    public var isUnpaid: Bool { attendanceStatus == .present && payment == nil }
}

public struct LessonState: Codable, Hashable, Sendable {
    public let lessonId: Int
    public let lessonPrice: Money
    public let status: LessonStatus
    public let presentCount: Int
    public let totalPrice: Money
    public let students: [LessonStudentState]

    public init(
        lessonId: Int, lessonPrice: Money, status: LessonStatus,
        presentCount: Int, totalPrice: Money, students: [LessonStudentState]
    ) {
        self.lessonId = lessonId
        self.lessonPrice = lessonPrice
        self.status = status
        self.presentCount = presentCount
        self.totalPrice = totalPrice
        self.students = students
    }

    public var hasUnmarkedStudents: Bool {
        students.contains { $0.attendanceStatus == nil }
    }
}

// MARK: - Карточка ученика

/// Ответ `students/{id}/history/`. Занятие здесь — не модель `Lesson`, а строка
/// истории конкретного ученика: к ней приклеены его отметка и его оплата.
public struct StudentHistory: Codable, Hashable, Sendable {
    public struct Stats: Codable, Hashable, Sendable {
        public let totalLessons: Int
        public let presentLessons: Int
        public let absentLessons: Int
        public let totalPaid: Money
        public let totalDebt: Money
        public let prepaidBalance: Money
    }

    public struct LessonRow: Codable, Hashable, Sendable, Identifiable {
        public let lessonId: Int
        public let date: CalendarDate
        public let time: DayTime
        public let duration: Int
        public let subject: String
        public let lessonPrice: Money
        public let status: LessonStatus
        public let attendanceStatus: AttendanceStatus?
        public let payment: PaymentSummary?

        public var id: Int { lessonId }

        /// Долг именно по этому занятию — то же правило, что в `Student.get_total_debt()`.
        public var isUnpaid: Bool {
            status == .scheduled && attendanceStatus == .present
                && payment == nil && lessonPrice.isPositive
        }
    }

    public struct PaymentRecord: Codable, Hashable, Sendable, Identifiable {
        public let id: Int
        public let lessonId: Int?
        public let amount: Money
        public let paymentDate: CalendarDate
        public let method: PaymentMethod
        public let methodDisplay: String
        public let isBalance: Bool
        public let notes: String
    }

    public let stats: Stats
    public let lessons: [LessonRow]
    public let payments: [PaymentRecord]
}

// MARK: - Долги

public struct StudentDebt: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let firstName: String
    public let lastName: String
    public let phone: String?
    public let debt: Money
    public let prepaidBalance: Money

    public var fullName: String { "\(lastName) \(firstName)".trimmingCharacters(in: .whitespaces) }
}

public struct DebtList: Codable, Hashable, Sendable {
    public let totalDebt: Money
    public let students: [StudentDebt]
}

public struct ClearDebtsResult: Codable, Hashable, Sendable {
    public let totalDebt: Money
    public let paidFromBalanceCount: Int
    public let paidFromBalanceAmount: Money
    public let paymentsCreated: Int
    public let paymentsAmount: Money
    public let studentBalance: Money
    public let totalDebtLeft: Money
}

// MARK: - Сводка и отчёты

public struct DashboardSummary: Codable, Hashable, Sendable {
    public let studentsCount: Int
    public let profitAllTime: Money
    public let profitMonth: Money
    public let profitWeek: Money
    public let lessonsAllTime: Int
    public let lessonsMonth: Int
    public let lessonsWeek: Int
}

public struct ProfitReport: Codable, Hashable, Sendable {
    public struct ByDay: Codable, Hashable, Sendable, Identifiable {
        public let paymentDate: CalendarDate
        public let total: Money
        public var id: String { paymentDate.serverValue }
    }

    public struct ByStudent: Codable, Hashable, Sendable, Identifiable {
        public let studentId: Int
        public let firstName: String
        public let lastName: String
        public let total: Money
        public var id: Int { studentId }
        public var fullName: String { "\(lastName) \(firstName)".trimmingCharacters(in: .whitespaces) }
    }

    public struct ByMethod: Codable, Hashable, Sendable, Identifiable {
        public let paymentMethod: PaymentMethod
        public let total: Money
        public var id: String { paymentMethod.rawValue }
    }

    public let startDate: CalendarDate
    public let endDate: CalendarDate
    public let totalProfit: Money
    public let profitByMethod: [ByMethod]
    public let profitByDay: [ByDay]
    public let profitByStudent: [ByStudent]
    public let lessonsCount: Int
    public let avgPerLesson: Money
    public let avgPerDay: Money
    public let daysCount: Int
}

// MARK: - Справочники

public struct MetaChoice: Codable, Hashable, Sendable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct APIMeta: Codable, Hashable, Sendable {
    public let apiVersion: String
    public let currency: String
    public let paymentMethods: [MetaChoice]
    public let cancellationReasons: [MetaChoice]
    public let lessonStatuses: [MetaChoice]
    public let attendanceStatuses: [MetaChoice]
    public let recurringPeriods: [MetaChoice]
}

// MARK: - Служебное

public struct Page<Item: Codable & Sendable>: Codable, Sendable {
    public let count: Int
    public let next: String?
    public let previous: String?
    public let results: [Item]

    public var hasMore: Bool { next != nil }
}

public struct CalendarMonth: Codable, Sendable {
    public let year: Int
    public let month: Int
    public let startDate: CalendarDate
    public let endDate: CalendarDate
    public let lessons: [Lesson]
}

/// Ответ `cancel/` и `restore/`. Это не занятие целиком: сервер возвращает
/// только изменившиеся поля, чтобы не гонять список учеников туда-обратно.
public struct LessonStatusChange: Codable, Hashable, Sendable {
    public let status: LessonStatus
    public let reason: String?
    public let reasonDisplay: String?
    public let note: String?
}

public struct RecurringLessonsResult: Codable, Sendable {
    public let createdCount: Int
    public let lessons: [Lesson]
}

public struct AuthToken: Codable, Sendable {
    public let token: String
}
