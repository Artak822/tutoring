import SwiftUI

/// Палитра. Основа — системные цвета iOS (они сами переключаются между темами и
/// уважают «увеличенный контраст»), а из DESIGN.md берём фирменный акцент и его
/// производные: ими красим то, что должно опознаваться как «наше» — кнопки,
/// сегодняшний день, денежные плитки.
enum Palette {
    /// Deep Violet из DESIGN.md. В тёмной теме — Soft Violet, иначе фиолетовый
    /// на чёрном фоне читается как грязное пятно. Обе версии лежат в AccentColor.
    static let brand = Color.accentColor

    /// Заливка под акцентом: фон выделенных плиток, «сегодня» в календаре, чипы.
    /// Прозрачность, а не отдельный цвет — так подложка одинаково работает
    /// и на белом, и на чёрном.
    static let brandSurface = Color.accentColor.opacity(0.12)

    /// Граница вокруг акцентных блоков. Washed Violet из DESIGN.md, но через
    /// прозрачность — чтобы в тёмной теме не светилась.
    static let brandBorder = Color.accentColor.opacity(0.28)

    /// Долг. Красный системный, а не «Vibrant Orange»: на iOS красный однозначно
    /// читается как «требует действия».
    static let debt = Color.red

    /// Предоплата — деньги в плюс.
    static let prepaid = Color.green

    /// Отменённое занятие.
    static let muted = Color.secondary

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let separator = Color(.separator)

    /// Точные значения из DESIGN.md — нужны там, где акцент рисуется градиентом
    /// и системный AccentColor не даёт нужного перехода.
    static let violetDeep = Color(red: 0.325, green: 0.227, blue: 0.992)   // #533afd
    static let violetSoft = Color(red: 0.502, green: 0.529, blue: 1.000)   // #8087ff
    static let violetWashed = Color(red: 0.725, green: 0.725, blue: 0.976) // #b9b9f9

    /// Заливка основных кнопок и логотипа.
    static let brandGradient = LinearGradient(
        colors: [violetDeep, violetSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Отступы по шкале DESIGN.md (база 4px).
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Скругления крупнее, чем 4px из веб-версии DESIGN.md: на телефоне острые углы
/// выглядят чужеродно рядом с системными карточками и самим корпусом устройства.
enum Radius {
    static let card: CGFloat = 16
    static let control: CGFloat = 12
    static let tag: CGFloat = 8
}

extension Font {
    /// Цифры в таблицах и суммах — моноширинные, чтобы колонки не прыгали.
    static func tabular(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }

    /// Заголовок раздела внутри экрана. Системный uppercase-заголовок секции
    /// теряется среди строк, а по нему ориентируются при беглом просмотре.
    static let sectionTitle = Font.subheadline.weight(.semibold)
}

extension Text {
    /// Денежная сумма: единый стиль по всему приложению.
    static func money(_ value: String, weight: Font.Weight = .semibold) -> Text {
        Text(value).font(.tabular(.body, weight: weight))
    }
}

extension View {
    /// Мягкая тень из DESIGN.md (`--shadow-sm`) — только для карточек, которые
    /// лежат поверх фона сами по себе. Внутри `List` система рисует подложку
    /// сама, и вторая тень там выглядит грязью.
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}
