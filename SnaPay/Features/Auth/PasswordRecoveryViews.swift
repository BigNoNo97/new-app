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
        VStack(spacing: Spacing.l) {
            if didSend {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: "סגירה") { dismiss() }
                }
                VStack(spacing: Spacing.m) {
                    FeatureIcon(symbol: "envelope", size: 84)
                    Text("שלחנו לך מייל")
                        .font(Typography.title1)
                        .foregroundStyle(Theme.textPrimary)
                    Text("שלחנו קישור לאיפוס אל **\(email)**. לחצו עליו כדי לבחור סיסמה חדשה.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button("חזרה להתחברות") { dismiss() }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("forgot.close")
                Button("לא הגיע? שלחו שוב", action: send)
                    .buttonStyle(.text)
                    .disabled(isSending)
            } else {
                SheetHeader(title: "איפוס סיסמה") { dismiss() }
                FeatureIcon(symbol: "lock", size: 64)
                Text("הזינו את כתובת המייל של החשבון, ונשלח קישור ליצירת סיסמה חדשה.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
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
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.l)
        .presentationDetents([.fraction(0.62), .large])
        .designSheet()
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
                        .font(Typography.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("לפחות 8 תווים, עם אותיות באנגלית ומספרים.")
                        .foregroundStyle(Theme.textSecondary)
                }
                GlassCard(padding: Spacing.gutter) {
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
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.xl)
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
            FeatureIcon(symbol: "envelope.open", size: 96)
            VStack(spacing: Spacing.s) {
                Text("בדקו את המייל")
                    .font(Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("שלחנו קישור לאישור החשבון אל **\(email)**. אחרי הלחיצה עליו, SnaPay ייפתח ותוכלו להמשיך.")
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("חזרה למסך הכניסה") { app.backToWelcome() }
                .buttonStyle(.glassSecondary)
                .accessibilityIdentifier("checkEmail.back")
        }
        .padding(Spacing.gutter)
    }
}
