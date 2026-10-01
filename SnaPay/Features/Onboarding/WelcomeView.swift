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
            // The hero gives way first on shorter screens, so the copy is never cut.
            WelcomeHero()
                .frame(minHeight: 250, maxHeight: 310)
                .layoutPriority(-1)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("כל הוצאה,\nבלחיצה אחת.")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // \u{200F} (RLM) keeps the paragraph right-to-left although it starts with a Latin word.
                Text("\u{200F}SnaPay קולט את התשלום מהאייפון, ואתה רק בוחר קטגוריה.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                FeatureLine(symbol: "wave.3.right", text: "תיעוד אוטומטי מ-Apple Pay")
                FeatureLine(symbol: "person.2", text: "ניהול משותף למשפחה")
                FeatureLine(symbol: "target", text: "יעדים ותקציבים")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: Spacing.sm) {
                Button("בוא נתחיל", action: onStart)
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("welcome.start")
                Button("יש לי כבר חשבון", action: onHaveAccount)
                    .buttonStyle(.glassSecondary)
                    .accessibilityIdentifier("welcome.logIn")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
        .background { AppBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FeatureLine: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.m) {
            FeatureIcon(symbol: symbol, size: 36)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Floating glass cards that tell the story at a glance: a payment with category tiles, the
/// saved chip, the month's bars, and the logo.
private struct WelcomeHero: View {
    @State private var isFloating = false

    private let tiles: [(String, UInt32)] = [("🛒", 0x2FB36D), ("🍔", 0xFF8A3D), ("🛍️", 0xE056B0), ("🏠", 0x8B5CF6)]

    // Offsets follow the layout direction: in Hebrew a positive x moves left.
    var body: some View {
        ZStack {
            // Month card (back, bottom left)
            GlassCard(padding: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("ספטמבר")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array([1.0, 0.6, 0.8, 1.0, 0.75, 0.45].enumerated()), id: \.offset) { index, height in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == 5 ? Theme.brand : Theme.fillStrong)
                                .frame(width: 18, height: 64 * height)
                        }
                    }
                    .frame(height: 64, alignment: .bottom)
                }
            }
            .frame(width: 170)
            .rotationEffect(.degrees(-4))
            .offset(x: 95, y: isFloating ? 88 : 96)

            // Payment card (front, top right)
            GlassCard(padding: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        EmojiTile(emoji: "🛒", color: Color(hex: "#2FB36D"), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("שופרסל דיל")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Label("Apple Pay · עכשיו", systemImage: "wave.3.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    AmountText(text: Money.string(Decimal(string: "212.40")!, currency: "ILS", alwaysShowCents: true),
                               font: .system(size: 34, weight: .bold))
                    HStack(spacing: Spacing.s) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                            EmojiTile(emoji: tile.0, color: Color(uiColor: UIColor(hex: tile.1)), size: 34)
                                .overlay {
                                    if index == 0 {
                                        RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.brand, lineWidth: 2).padding(-3)
                                    }
                                }
                        }
                    }
                }
            }
            .frame(width: 245)
            .rotationEffect(.degrees(2))
            .offset(x: -45, y: isFloating ? -62 : -54)

            // Saved chip
            HStack(spacing: Spacing.s) {
                EmojiTile(emoji: "🍔", color: Color(hex: "#FF8A3D"), size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("אוכל ומסעדות")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Label("נשמר", systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.brandInk)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .glassSurface(radius: 18)
            .offset(x: -40, y: isFloating ? 92 : 100)

            // Logo tile
            BrandTile(size: 52)
                .offset(x: 100, y: isFloating ? -118 : -112)
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
