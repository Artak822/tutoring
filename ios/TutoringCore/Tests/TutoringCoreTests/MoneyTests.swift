import Testing
import Foundation
@testable import TutoringCore

@Suite("Деньги")
struct MoneyTests {

    @Test("Строка с сервера разбирается без потери копеек")
    func parsesServerString() throws {
        let money = try #require(Money(string: "1500.55"))
        #expect(money.amount == Decimal(string: "1500.55"))
        #expect(money.formattedForServer == "1500.55")
    }

    @Test("Целые суммы уходят на сервер с двумя знаками")
    func formatsWholeAmounts() {
        #expect(Money(1500).formattedForServer == "1500.00")
        #expect(Money.zero.formattedForServer == "0.00")
    }

    @Test("Запятая как разделитель не ломает разбор — сервер всегда шлёт точку")
    func rejectsUnexpectedSeparator() {
        // Decimal с локалью en_US_POSIX прочитает «1500,55» как 1500 — важно, что не упадёт
        let money = Money(string: "1500,55")
        #expect(money?.amount == Decimal(1500))
    }

    @Test("Сложение сумм точное, в отличие от Double")
    func addsWithoutDriftError() throws {
        let a = try #require(Money(string: "0.10"))
        let b = try #require(Money(string: "0.20"))
        #expect((a + b).formattedForServer == "0.30")
    }

    @Test("Декодируется из JSON-строки")
    func decodesFromJSON() throws {
        struct Wrapper: Decodable { let amount: Money }
        let data = Data(#"{"amount": "2400.00"}"#.utf8)
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        #expect(wrapper.amount.amount == Decimal(2400))
    }

    @Test("Кодируется обратно строкой, а не числом")
    func encodesAsString() throws {
        struct Wrapper: Encodable { let amount: Money }
        let data = try JSONEncoder().encode(Wrapper(amount: Money(999)))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"999.00\""))
    }

    @Test("Для интерфейса копейки показываются только когда они есть")
    func formatsForDisplay() throws {
        #expect(Money(1500).formatted() == "1\u{00A0}500 ₽")
        #expect(try #require(Money(string: "1500.50")).formatted() == "1\u{00A0}500,50 ₽")
        #expect(Money(1500).formatted(currency: "") == "1\u{00A0}500")
    }

    @Test("Состояние баланса ученика совпадает с бейджами в вебе")
    func balanceState() throws {
        func student(debt: String, prepaid: String) -> Student {
            Student(
                id: 1, groups: [], firstName: "Иван", lastName: "Петров",
                phone: nil, telegram: nil, grade: nil, notes: "", isActive: true,
                defaultPrice: nil, prepaidBalance: Money(string: prepaid)!,
                totalPaid: .zero, totalDebt: Money(string: debt)!
            )
        }
        #expect(student(debt: "1500.00", prepaid: "0.00").balanceState == .debt(Money(1500)))
        #expect(student(debt: "0.00", prepaid: "800.00").balanceState == .prepaid(Money(800)))
        #expect(student(debt: "0.00", prepaid: "0.00").balanceState == .clear)
    }
}
