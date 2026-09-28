import SwiftUI

enum AuthScreen: Hashable {
    case signUp
    case logIn
}

/// Welcome → sign-up / log-in, in one navigation stack.
struct WelcomeFlowView: View {
    @State private var path: [AuthScreen] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onStart: { path.append(.signUp) },
                onHaveAccount: { path.append(.logIn) }
            )
            .navigationDestination(for: AuthScreen.self) { screen in
                switch screen {
                case .signUp:
                    SignUpView(onSwitchToLogIn: { path = [.logIn] })
                case .logIn:
                    LogInView(onSwitchToSignUp: { path = [.signUp] })
                }
            }
        }
    }
}

struct WelcomeView: View {
    var onStart: () -> Void
    var onHaveAccount: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            WelcomeHero()
                .frame(maxHeight: 320)
                .padding(.top, Spacing.l)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("כל הוצאה, בלחיצה אחת.")
                    .font(.largeTitle.weight(.bold))
                Text("SnaPay קולט את התשלום מהאייפון, ואתה רק בוחר קטגוריה.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.m) {
                FeatureLine(symbol: "wave.3.right", text: "תיעוד אוטומטי מ-Apple Pay")
                FeatureLine(symbol: "person.2.fill", text: "ניהול משותף לזוג ולמשפחה")
                FeatureLine(symbol: "target", text: "יעדים ותקציבים שעוזרים לחסוך")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: Spacing.m) {
                Button("בוא נתחיל", action: onStart)
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("welcome.start")
                Button("יש לי כבר חשבון", action: onHaveAccount)
                    .buttonStyle(.glassSecondary)
                    .accessibilityIdentifier("welcome.logIn")
            }
        }
        .padding(Spacing.m)
        .background { AppBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FeatureLine: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Theme.brand.opacity(0.14), in: .rect(cornerRadius: 10))
            Text(text)
                .font(.body.weight(.medium))
        }
    }
}

/// Floating glass cards that tell the story at a glance: a payment, its category, the month.
private struct WelcomeHero: View {
    @State private var isFloating = false

    var body: some View {
        ZStack {
            // Month card (back)
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("ספטמבר")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("₪3,453")
                        .font(.title2.weight(.semibold))
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array([0.35, 0.55, 0.4, 0.8, 0.6, 1.0].enumerated()), id: \.offset) { index, height in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(index == 5 ? Theme.brand : Theme.brand.opacity(0.25))
                                .frame(width: 18, height: 48 * height)
                        }
                    }
                    .frame(height: 48, alignment: .bottom)
                }
            }
            .frame(width: 210)
            .rotationEffect(.degrees(-6))
            .offset(x: -70, y: isFloating ? -54 : -46)

            // Payment card (front)
            GlassCard {
                HStack(spacing: Spacing.m) {
                    Text("☕")
                        .font(.title)
                        .frame(width: 48, height: 48)
                        .background(Theme.expense.opacity(0.16), in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ארומה")
                            .font(.headline)
                        Text("Apple Pay · עכשיו")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("₪18.50")
                        .font(.headline)
                }
            }
            .frame(width: 290)
            .offset(x: 20, y: isFloating ? 38 : 46)

            // Category chip
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.brand)
                Text("נשמר בקפה")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .offset(x: 90, y: isFloating ? 118 : 124)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            // Endless animations keep UI tests from ever seeing the app idle.
            guard !AppConfig.isUITesting else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }
}
