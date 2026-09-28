import SwiftUI
import SnaPayCore

/// "Forgot password?" → sends a reset link by email.
struct ForgotPasswordSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var issue: CredentialsIssue?
    @State private var failure: AuthFailure?
    @State private var isSending = false
    @State private var didSend = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if didSend {
                VStack(spacing: Spacing.m) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.brand)
                    Text("שלחנו לך מייל")
                        .font(.title2.weight(.bold))
                    Text("פתחו את הקישור במייל כדי לבחור סיסמה חדשה. הקישור יפתח את SnaPay.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.l)

                Button("סגירה") { dismiss() }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("forgot.close")
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("איפוס סיסמה")
                        .font(.title2.weight(.bold))
                    Text("נשלח לך קישור לבחירת סיסמה חדשה.")
                        .foregroundStyle(.secondary)
                }
                GlassTextField(title: "אימייל", text: $email, kind: .email, issue: issue, identifier: "forgot.email")
                if let failure {
                    ErrorBanner(message: failure.message)
                }
                Button(action: send) {
                    LoadingLabel(title: "שלחו לי קישור לאיפוס", isLoading: isSending)
                }
                .buttonStyle(.primary)
                .disabled(isSending)
                .accessibilityIdentifier("forgot.send")
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
        .presentationDetents([.medium])
        .presentationBackground(.regularMaterial)
    }

    private func send() {
        issue = CredentialsValidator.emailIssue(email)
        failure = nil
        guard issue == nil else { return }
        isSending = true
        Task {
            do {
                try await app.sendPasswordReset(email: email)
                withAnimation { didSend = true }
            } catch {
                failure = error as? AuthFailure ?? .unknown
            }
            isSending = false
        }
    }
}

/// Opened from the reset link: choose a new password.
struct ResetPasswordView: View {
    @Environment(AppState.self) private var app

    @State private var password = ""
    @State private var confirmation = ""
    @State private var validation = CredentialsValidation()
    @State private var failure: AuthFailure?
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("סיסמה חדשה")
                        .font(.largeTitle.weight(.bold))
                    Text("לפחות 8 תווים, עם אותיות באנגלית ומספרים.")
                        .foregroundStyle(.secondary)
                }
                GlassCard(padding: Spacing.l) {
                    VStack(spacing: Spacing.m) {
                        GlassTextField(title: "סיסמה חדשה", text: $password, kind: .newPassword,
                                       issue: validation.password, identifier: "reset.password")
                        GlassTextField(title: "אימות סיסמה", text: $confirmation, kind: .newPassword,
                                       issue: validation.passwordConfirmation, identifier: "reset.confirmation")
                    }
                }
                if let failure {
                    ErrorBanner(message: failure.message)
                }
                Button(action: save) {
                    LoadingLabel(title: "שמירת הסיסמה", isLoading: isSaving)
                }
                .buttonStyle(.primary)
                .disabled(isSaving)
                .accessibilityIdentifier("reset.save")
            }
            .padding(Spacing.m)
        }
        .background { AppBackground() }
    }

    private func save() {
        validation = CredentialsValidator.validateNewPassword(password, confirmation: confirmation)
        failure = nil
        guard validation.isValid else { return }
        isSaving = true
        Task {
            do {
                try await app.updatePassword(password)
            } catch {
                failure = error as? AuthFailure ?? .unknown
            }
            isSaving = false
        }
    }
}

/// After sign-up when the server requires email confirmation.
struct CheckEmailView: View {
    @Environment(AppState.self) private var app
    let email: String

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.brand)
                .frame(width: 112, height: 112)
                .glassEffect(.regular, in: .rect(cornerRadius: 32))
            VStack(spacing: Spacing.s) {
                Text("בדקו את המייל")
                    .font(.largeTitle.weight(.bold))
                Text("שלחנו קישור לאישור החשבון אל \(email). אחרי הלחיצה עליו, SnaPay ייפתח ותוכלו להמשיך.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("חזרה למסך הכניסה") { app.backToWelcome() }
                .buttonStyle(.glass)
                .accessibilityIdentifier("checkEmail.back")
        }
        .padding(Spacing.m)
    }
}
