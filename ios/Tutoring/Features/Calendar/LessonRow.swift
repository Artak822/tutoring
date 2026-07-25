import SwiftUI
import TutoringCore

/// Строка занятия в списке дня. Слева — время, справа — ученики и деньги.
struct LessonRow: View {
    let lesson: Lesson
    let studentNames: String
    let currency: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            timeBlock

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(studentNames)
                    .font(.body.weight(.medium))
                    .strikethrough(lesson.isCancelled, color: Palette.muted)
                    .foregroundStyle(lesson.isCancelled ? Color.secondary : .primary)

                if !lesson.subject.isEmpty {
                    Text(lesson.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.s) {
                    if lesson.isCancelled {
                        Badge(
                            text: lesson.cancellationReasonDisplay ?? "Отменено",
                            systemImage: "xmark.circle",
                            tint: Palette.muted
                        )
                    } else {
                        Text(lesson.plannedPrice.formatted(currency: currency))
                            .font(.tabular(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if lesson.isGroupLesson {
                            Badge(
                                text: plural(lesson.students.count, "ученик", "ученика", "учеников"),
                                systemImage: "person.2"
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    /// Время в цветной плашке вместо голого текста с полоской рядом: так строка
    /// сканируется по левому краю за один проход, а статус занятия читается
    /// цветом плашки, а не отдельным значком.
    private var timeBlock: some View {
        VStack(spacing: 1) {
            Text(lesson.time.serverValue)
                .font(.tabular(.subheadline, weight: .semibold))
                .foregroundStyle(lesson.isCancelled ? Color.secondary : Palette.brand)
            Text(DateText.duration(lesson.duration))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 58)
        .padding(.vertical, Spacing.s)
        .background(
            lesson.isCancelled ? Color(.tertiarySystemFill) : Palette.brandSurface,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
    }
}
