import SwiftUI
import TutoringCore

struct RegisterView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var password1 = ""
    @State private var password2 = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    private var canSubmit: Bool {
        ![username, email, firstName, lastName, password1, password2]
            .contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Аккаунт") {
                    TextField("Логин", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("О себе") {
                    TextField("Имя", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Фамилия", text: $lastName)
                        .textContentType(.familyName)
                    TextField("Телефон (необязательно)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Section {
                    SecureField("Пароль", text: $password1)
                        .textContentType(.newPassword)
                    SecureField("Повторите пароль", text: $password2)
                        .textContentType(.newPassword)
                } header: {
                    Text("Пароль")
                } footer: {
                    // Правила проверяет Django, дублировать их здесь — верный способ разойтись
                    Text("Не короче 8 символов, не только цифры.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Palette.debt)
                    }
                }

                Section {
                    Button("Зарегистрироваться", action: submit)
                        .buttonStyle(.primary)
                        .disabled(!canSubmit)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .busy(isBusy)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        errorMessage = nil

        guard password1 == password2 else {
            errorMessage = "Пароли не совпадают"
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await session.register(
                    RegisterRequest(
                        username: username.trimmingCharacters(in: .whitespaces),
                        email: email.trimmingCharacters(in: .whitespaces),
                        firstName: firstName.trimmingCharacters(in: .whitespaces),
                        lastName: lastName.trimmingCharacters(in: .whitespaces),
                        phone: phone.trimmingCharacters(in: .whitespaces),
                        password1: password1,
                        password2: password2
                    )
                )
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

#Preview {
    RegisterView()
        .environment(Session(cache: OfflineCache()))
}
