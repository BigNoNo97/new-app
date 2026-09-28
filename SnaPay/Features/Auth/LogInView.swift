import SwiftUI
import SnaPayCore

struct LogInView: View {
    @Environment(AppState.self) private var app
    var onSwitchToSignUp: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false

    @State private var validation = CredentialsValidation()
    @State private var hasTriedSubmitting = false
    @State private var failure: AuthFailure?
    @State private var isSubmitting = false
    @State private var isShowingForgotPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("טוב לראות אותך שוב")
                        .font(.largeTitle.weight(.bold))
                    Text("מתחברים וממשיכים מאיפה שהפסקת.")
                        .foregroundStyle(.secondary)
                }

                GlassCard(padding: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GlassTextField(title: "אימייל", text: $email, kind: .email,
                                       issue: validation.email, identifier: "login.email")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            GlassTextField(title: "סיסמה", text: $password, kind: .password,
                                           issue: validation.password, identifier: "login.password")
                            Button("שכחת סיסמה?") { isShowingForgotPassword = true }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.brand)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("login.forgot")
                        }
                        TermsConsentRow(isOn: $acceptedTerms, issue: validation.terms)
                    }
                }

                if let failure {
                    ErrorBanner(message: failure.message)
                }

                Button(action: submit) {
                    LoadingLabel(title: "התחברות", isLoading: isSubmitting)
                }
                .buttonStyle(.primary)
                .disabled(isSubmitting)
                .accessibilityIdentifier("login.submit")

                HStack(spacing: Spacing.xs) {
                    Text("אין לך חשבון עדיין?")
                        .foregroundStyle(.secondary)
                    Button("לחץ להרשמה", action: onSwitchToSignUp)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.brand)
                        .accessibilityIdentifier("login.toSignUp")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingForgotPassword) {
            ForgotPasswordSheet(initialEmail: email)
        }
        .onChange(of: [email, password]) { revalidateIfNeeded() }
        .onChange(of: acceptedTerms) { revalidateIfNeeded() }
    }

    private func validate() -> CredentialsValidation {
        CredentialsValidator.validateLogIn(email: email, password: password, acceptedTerms: acceptedTerms)
    }

    private func revalidateIfNeeded() {
        if hasTriedSubmitting { validation = validate() }
    }

    private func submit() {
        hasTriedSubmitting = true
        validation = validate()
        failure = nil
        guard validation.isValid else { return }
        isSubmitting = true
        Task {
            do {
                try await app.logIn(email: email, password: password)
            } catch {
                failure = error as? AuthFailure ?? .unknown
            }
            isSubmitting = false
        }
    }
}
