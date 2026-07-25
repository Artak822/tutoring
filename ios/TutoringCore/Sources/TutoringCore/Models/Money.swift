import Foundation

/// Денежная сумма. Бэкенд отдаёт деньги строками («1500.00»), и это принципиально:
/// `Double` на суммах вроде 0.1 + 0.2 даёт копеечные расхождения, а тут сходятся балансы
/// предоплаты и долги. Внутри — только `Decimal`.
public struct Money: Hashable, Sendable, Comparable {
    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }

    public init?(string: String) {
        // Сервер всегда шлёт точку как разделитель, локаль тут ни при чём
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self.amount = value
    }

    public static let zero = Money(.zero)

    public var isZero: Bool { amount == .zero }
    public var isPositive: Bool { amount > .zero }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.amount < rhs.amount }
    public static func + (lhs: Money, rhs: Money) -> Money { Money(lhs.amount + rhs.amount) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(lhs.amount - rhs.amount) }
}

extension Money: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Основной формат — строка. Число допускаем на случай, если какое-то поле
        // однажды начнёт приходить числом: лучше разобрать, чем упасть на всём экране.
        if let string = try? container.decode(String.self) {
            guard let money = Money(string: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Не удалось разобрать сумму: \(string)"
                )
            }
            self = money
        } else {
            let double = try container.decode(Double.self)
            self.init(Decimal(double))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(formattedForServer)
    }

    /// Формат, в котором сервер ждёт суммы в теле запроса: ровно два знака и точка.
    /// `NSDecimalNumber.description` тут не годится — он режет хвостовые нули («1500»
    /// вместо «1500.00»), а Django на DecimalField такое принимает не везде.
    public var formattedForServer: String {
        Self.serverFormatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00"
    }

    private static let serverFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter
    }()
}

extension Money {
    /// Сумма для интерфейса: «1 500 ₽», копейки показываем только когда они есть.
    public func formatted(currency: String = "₽") -> String {
        let number = NSDecimalNumber(decimal: amount)
        let hasFraction = amount != amount.rounded(scale: 0)
        let formatter = hasFraction ? Self.displayFractionFormatter : Self.displayFormatter
        let text = formatter.string(from: number) ?? "0"
        return currency.isEmpty ? text : "\(text) \(currency)"
    }

    private static func makeDisplayFormatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "\u{00A0}"  // неразрывный пробел, чтобы сумма не рвалась
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter
    }

    private static let displayFormatter = makeDisplayFormatter(fractionDigits: 0)
    private static let displayFractionFormatter = makeDisplayFormatter(fractionDigits: 2)
}

extension Decimal {
    fileprivate func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}

extension Money: CustomStringConvertible {
    public var description: String { formattedForServer }
}
