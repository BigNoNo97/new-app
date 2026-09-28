import SwiftUI
import SnaPayCore

struct SignUpView: View {
    @Environment(AppState.self) private var app
    var onSwitchToLogIn: () -> Void

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var currency = "ILS"
    @State private var acceptedTerms = false

    @State private var validation = CredentialsValidation()
    @State private var hasTriedSubmitting = false
    @State private var failure: AuthFailure?
    @State private var isSubmitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("יצירת חשבון")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("דקה אחת, ואפשר להתחיל לתעד.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                GlassCard(padding: Spacing.gutter) {
                    VStack(spacing: Spacing.m) {
                        GlassTextField(title: "שם מלא", text: $fullName, kind: .name,
                                       issue: validation.fullName, identifier: "signup.fullName")
                        GlassTextField(title: "אימייל", text: $email, kind: .email,
                                       issue: validation.email, identifier: "signup.email")
                        GlassTextField(title: "סיסמה", text: $password, kind: .newPassword,
                                       issue: validation.password, identifier: "signup.password")
                        GlassTextField(title: "אימות סיסמה", text: $confirmation, kind: .newPassword,
                                       issue: validation.passwordConfirmation, identifier: "signup.confirmation")
                        CurrencyPickerRow(title: "המטבע העיקרי שלי", code: $currency)
                    }
                }

                TermsConsentRow(isOn: $acceptedTerms, issue: validation.terms)

                if let failure {
                    ErrorBanner(message: failure.message)
                }

                Button(action: submit) {
                    LoadingLabel(title: "הרשמה", isLoading: isSubmitting)
                }
                .buttonStyle(.primary)
                .disabled(isSubmitting)
                .accessibilityIdentifier("signup.submit")

                HStack(spacing: Spacing.xs) {
                    Text("כבר יש לך חשבון?")
                        .foregroundStyle(Theme.textSecondary)
                    Button("להתחברות", action: onSwitchToLogIn)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.brandInk)
                        .accessibilityIdentifier("signup.toLogIn")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .designBackButton()
        .onChange(of: [fullName, email, password, confirmation]) { revalidateIfNeeded() }
        .onChange(of: acceptedTerms) { revalidateIfNeeded() }
    }

    private func validate() -> CredentialsValidation {
        CredentialsValidator.validateSignUp(
            fullName: fullName, email: email, password: password,
            passwordConfirmation: confirmation, acceptedTerms: acceptedTerms
        )
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
                try await app.signUp(fullName: fullName, email: email, password: password, mainCurrency: currency)
            } catch {
                failure = error as? AuthFailure ?? .unknown
            }
            isSubmitting = false
        }
    }
}
