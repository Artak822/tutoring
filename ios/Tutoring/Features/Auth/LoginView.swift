import SwiftUI
import TutoringCore

/// Вход. Единственный экран, который видят до данных, поэтому он и представляет
/// приложение: фирменная шапка, одна карточка с полями и один явный шаг дальше.
struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var isShowingRegistration = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                background

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        header
                        credentialsCard

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        VStack(spacing: Spacing.m) {
                            Button("Войти", action: submit)
                                .buttonStyle(.primary)
                                .disabled(!canSubmit)

                            registrationLink
                        }

                        serverPicker
                            .padding(.top, Spacing.s)
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xxl)
                    .animation(.easeOut(duration: 0.2), value: errorMessage)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
            .busy(isBusy)
            .sheet(isPresented: $isShowingRegistration) {
                RegisterView()
            }
        }
    }

    // MARK: - Оформление

    /// Фирменный цвет только вверху и почти прозрачный: экран должен читаться
    /// как «наш», но поля ввода стоят на привычном системном фоне.
    private var background: some View {
        ZStack(alignment: .top) {
            Palette.groupedBackground
            LinearGradient(
                colors: [Palette.violetDeep.opacity(0.16), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: Spacing.l) {
            AppMark(size: 64)

            VStack(spacing: Spacing.xs) {
                Text("Репетитор")
                    .font(.title.weight(.bold))
                Text("Занятия, оплаты и долги — в одном месте")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, Spacing.xxl)
    }

    /// Логин и пароль в одной карточке с разделителем — как системная форма:
    /// два отдельных блока с подписями делали экран длинным и рыхлым.
    private var credentialsCard: some View {
        VStack(spacing: 0) {
            FieldRow(systemImage: "person", isFocused: focusedField == .username) {
                TextField("Логин", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
            }

            Divider()
                .padding(.leading, Spacing.l + 22 + Spacing.m)

            FieldRow(systemImage: "lock", isFocused: focusedField == .password) {
                HStack(spacing: Spacing.s) {
                    Group {
                        if isPasswordVisible {
                            TextField("Пароль", text: $password)
                        } else {
                            SecureField("Пароль", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submit() }

                    Button {
                        isPasswordVisible.toggle()
                        // Подмена SecureField на TextField пересоздаёт поле,
                        // и фокус слетает — возвращаем его следующим тактом.
                        Task { @MainActor in focusedField = .password }
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Скрыть пароль" : "Показать пароль")
                }
            }
        }
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(focusedField == nil ? Palette.separator : Palette.brandBorder, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: focusedField)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(Palette.debt)
        .padding(Spacing.m)
        .background(Palette.debt.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Регистрация — редкий сценарий, поэтому строкой, а не второй кнопкой
    /// в полный рост: раньше она спорила за внимание с «Войти».
    private var registrationLink: some View {
        HStack(spacing: Spacing.xs) {
            Text("Ещё нет аккаунта?")
                .foregroundStyle(.secondary)
            Button("Создать") { isShowingRegistration = true }
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    /// Выбор сервера доступен только в Debug: в релизе список из одного элемента.
    /// Свёрнут в подпись внизу — это отладочная мелочь, а не часть входа.
    @ViewBuilder
    private var serverPicker: some View {
        if ServerEnvironment.availableEnvironments.count > 1 {
            Menu {
                ForEach(ServerEnvironment.availableEnvironments) { environment in
                    Button {
                        Task { await session.switchEnvironment(to: environment) }
                    } label: {
                        if environment == session.environment {
                            Label(environment.title, systemImage: "checkmark")
                        } else {
                            Text(environment.title)
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(session.environment == .production ? Palette.prepaid : Palette.brand)
                            .frame(width: 6, height: 6)
                        Text(session.environment.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                    Text(session.environment.baseURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Действия

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        errorMessage = nil
        isBusy = true

        Task {
            defer { isBusy = false }
            do {
                try await session.signIn(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch {
                errorMessage = message(for: error)
                password = ""
            }
        }
    }

    /// Общие формулировки ошибок здесь врут: на экране входа «Запись не найдена»
    /// выглядит как «нет такого пользователя», хотя означает, что по этому адресу
    /// нет API — например, на стенде развёрнута версия бэкенда без него.
    private func message(for error: Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        let host = session.environment.baseURL.host() ?? session.environment.baseURL.absoluteString

        switch apiError {
        case .notFound:
            return "\(host) отвечает, но не отдаёт API приложения. Похоже, там развёрнута старая версия сервера."
        case .offline, .timeout:
            return "\(host) не отвечает. Проверьте связь или выберите другой сервер."
        case .unauthorized:
            return "Неверный логин или пароль."
        default:
            return apiError.errorDescription ?? error.localizedDescription
        }
    }
}

/// Строка карточки входа: значок слева, поле справа. Значок подсвечивается
/// акцентом в фокусе — вместо рамки вокруг всего поля.
private struct FieldRow<Field: View>: View {
    let systemImage: String
    var isFocused = false
    @ViewBuilder var field: Field

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFocused ? Palette.brand : .secondary)
                .frame(width: 22)
            field
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m + 2)
    }
}

#Preview {
    LoginView()
        .environment(Session(cache: OfflineCache()))
}
