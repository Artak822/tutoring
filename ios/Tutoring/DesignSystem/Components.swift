import SwiftUI

// MARK: - Кнопки

/// Основное действие: залитая фирменным градиентом кнопка на всю ширину.
/// Градиент, а не плоский акцент, — единственное место, где приложение
/// позволяет себе украшательство: так главная кнопка экрана не спутывается
/// ни с чем другим.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.m + 2)
            .background(Palette.brandGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            // Тень цветом кнопки, а не чёрным: чёрная под фиолетовым выглядит грязью.
            .shadow(
                color: Palette.violetDeep.opacity(isEnabled ? 0.3 : 0),
                radius: 12, x: 0, y: 6
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Второстепенное действие: контур акцентом.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.m)
            .foregroundStyle(Palette.brand)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Palette.brandBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

// MARK: - Фирменные метки

/// Значок приложения внутри интерфейса — заставка, шапка входа.
/// Повторяет иконку на домашнем экране, чтобы вход не выглядел чужим окном.
struct AppMark: View {
    var size: CGFloat = 72

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Palette.brandGradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: Palette.violetDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Бейджи

/// Плашка вроде «Долг 1 500 ₽» или «Отменено».
struct Badge: View {
    let text: String
    var systemImage: String?
    var tint: Color = Palette.brand

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
    }
}

// MARK: - Карточка

struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Плитка «подпись сверху, число снизу» — сводка и итоги отчёта.
/// Число крупное и моноширинное: на эти цифры и смотрят, всё остальное подпись.
struct StatTile: View {
    let caption: String
    let value: String
    var tint: Color = .primary
    var isHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.tabular(.title3, weight: .semibold))
                .foregroundStyle(isHighlighted ? Palette.brand : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(isHighlighted ? Palette.brandSurface : Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

// MARK: - Состояния экрана

/// Пустой экран: единый вид для «нет занятий», «нет учеников», «нет долгов».
struct EmptyStateView: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.brand)
            }
        }
    }
}

/// Ошибка загрузки с возможностью повторить.
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Не получилось загрузить", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Повторить", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.brand)
            }
        }
    }
}

/// Полоска над списком, когда сервер недоступен, а данные показаны с диска.
/// Экран ошибки тут был бы враньём: занятия на месте, просто они не сегодняшние.
struct OfflineNoticeView: View {
    let updatedAt: Date

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
            Text("Нет связи. Данные от \(DateText.relative(updatedAt))")
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity)
        .background(Palette.muted.opacity(0.12))
    }
}

// MARK: - Поля ввода

/// Поле формы с подписью — используется на входе и регистрации.
/// Рамка подсвечивается акцентом в фокусе: без неё на светлой карточке
/// не видно, куда именно пойдёт следующий символ.
struct LabeledField<Field: View>: View {
    let title: String
    var isFocused = false
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            field
                .textFieldStyle(.plain)
                .padding(Spacing.m)
                .background(Palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(isFocused ? Palette.brand : Palette.separator, lineWidth: isFocused ? 2 : 1)
                }
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

// MARK: - Служебное

extension View {
    /// Блокирует экран на время сетевого запроса, не подменяя содержимое спиннером.
    func busy(_ isBusy: Bool) -> some View {
        disabled(isBusy)
            .overlay {
                if isBusy {
                    ProgressView()
                        .controlSize(.large)
                        .padding(Spacing.xl)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
                }
            }
    }
}
