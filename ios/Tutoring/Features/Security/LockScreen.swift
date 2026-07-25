import SwiftUI

/// Шторка поверх приложения, пока личность не подтверждена.
/// Непрозрачный фон обязателен: сквозь него не должно просвечивать расписание
/// ни на экране, ни в снимке для переключателя задач.
struct LockScreen: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: Spacing.l) {
            Circle()
                .fill(Palette.brandSurface)
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Palette.brand)
                }

            Text("Приложение заблокировано")
                .font(.title3.weight(.semibold))

            if let message = lock.failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.debt)
                    .multilineTextAlignment(.center)
            }

            Button("Разблокировать") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.primary)
            .frame(maxWidth: 260)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground)
        .task {
            // Холодный старт: спрашиваем сразу, лишний тап тут ни к чему.
            // Шторка появляется и при уходе в фон — там запрос показать негде,
            // и его делает сцена, когда приложение снова станет активным.
            guard scenePhase == .active else { return }
            await lock.unlock()
        }
    }
}
