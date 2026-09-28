import SwiftUI
import SnaPayCore

/// A labeled glass text field with an inline error. Password kinds get an eye button that
/// shows or hides the password.
struct GlassTextField: View {
    enum Kind {
        case name, email, password, newPassword

        var isSecure: Bool { self == .password || self == .newPassword }
    }

    let title: LocalizedStringKey
    @Binding var text: String
    var kind: Kind = .name
    var issue: CredentialsIssue?
    var identifier: String

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Spacing.s) {
                field
                    .font(.body)
                    .textInputAutocapitalization(kind == .name ? .words : .never)
                    .autocorrectionDisabled(kind != .name)
                    .keyboardType(kind == .email ? .emailAddress : .default)
                    .textContentType(contentType)
                    .focused($isFocused)
                    .accessibilityIdentifier(identifier)

                if kind.isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRevealed ? Text("הסתרת הסיסמה") : Text("הצגת הסיסמה"))
                    .accessibilityIdentifier("\(identifier).reveal")
                }
            }
            .fieldSurface(state: issue != nil ? .error : (isFocused ? .focused : .normal))

            if let issue {
                FieldErrorText(message: issue.message)
                    .accessibilityIdentifier("\(identifier).error")
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if kind.isSecure && !isRevealed {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }

    private var contentType: UITextContentType {
        switch kind {
        case .name: .name
        case .email: .username
        case .password: .password
        case .newPassword: .newPassword
        }
    }
}

/// Square checkbox (rounded corners) with a label that may contain links.
struct CheckboxRow<Label: View>: View {
    @Binding var isOn: Bool
    var issue: CredentialsIssue?
    var identifier: String
    @ViewBuilder var label: Label

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: Spacing.s + 2) {
                Button {
                    isOn.toggle()
                } label: {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isOn ? Theme.buttonPrimary : (issue == nil ? Theme.textTertiary : Theme.destructive), lineWidth: 1.5)
                        .background(isOn ? Theme.buttonPrimary : Theme.field, in: .rect(cornerRadius: 7))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.onButtonPrimary)
                            }
                        }
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
                .accessibilityAddTraits(isOn ? .isSelected : [])

                label
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            if let issue {
                FieldErrorText(message: issue.message)
            }
        }
    }
}

/// The terms & privacy consent row used on sign-up and log-in.
struct TermsConsentRow: View {
    @Binding var isOn: Bool
    var issue: CredentialsIssue?

    /// Built as markdown at runtime: links in a LocalizedStringKey can't take interpolated URLs.
    private static let consentText: AttributedString = {
        let markdown = "קראתי ואני מאשר/ת את [תנאי השימוש](\(AppConfig.termsURL.absoluteString)) ואת [מדיניות הפרטיות](\(AppConfig.privacyURL.absoluteString))"
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }()

    var body: some View {
        CheckboxRow(isOn: $isOn, issue: issue, identifier: "terms.checkbox") {
            Text(Self.consentText)
                .tint(Theme.brandInk)
        }
    }
}

/// A category tile: emoji in a tinted square, name below. Selected tiles get a brand border
/// and a check badge.
struct CategoryTile: View {
    let draft: CategoryDraft
    var isSelected: Bool

    var body: some View {
        VStack(spacing: Spacing.s) {
            EmojiTile(emoji: draft.emoji, color: Color(hex: draft.colorHex), size: 40)
            Text(draft.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .glassSurface(radius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSelected ? Theme.brand : Color.clear, lineWidth: 2)
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.onButtonPrimary)
                    .frame(width: 20, height: 20)
                    .background(Theme.buttonPrimary, in: .rect(cornerRadius: 6))
                    .padding(8)
            }
        }
    }
}

/// An emoji inside a tinted rounded square (16% of the category color in light mode, 22% in
/// dark), with a faint border in the same color. Sizes 30 / 40 / 48 / 64 in the design.
struct EmojiTile: View {
    let emoji: String
    let color: Color
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Theme.categoryTint(color, scheme: scheme), in: .rect(cornerRadius: size * 0.32))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32)
                    .strokeBorder(color.opacity(0.22), lineWidth: 1)
            }
    }
}

/// Field surface states from the design: normal, focused (green border and a 4pt ring) and
/// error (red border and ring).
enum FieldState {
    case normal, focused, error
}

extension View {
    func fieldSurface(state: FieldState = .normal) -> some View {
        let border: Color = switch state {
        case .normal: Theme.stroke
        case .focused: Theme.brand
        case .error: Theme.destructive
        }
        return self
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.fieldHeight)
            .background(Theme.field, in: .rect(cornerRadius: Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.field)
                    .strokeBorder(border, lineWidth: state == .normal ? 1 : 1.5)
            }
            .background {
                if state != .normal {
                    RoundedRectangle(cornerRadius: Radius.field + 4)
                        .fill(border.opacity(0.16))
                        .padding(-4)
                }
            }
            .animation(.easeOut(duration: 0.15), value: state)
    }
}

/// The red message under a field, with a warning icon.
struct FieldErrorText: View {
    let message: LocalizedStringKey

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.expense)
    }
}

/// Picker row for the user's main currency.
struct CurrencyPickerRow: View {
    let title: LocalizedStringKey
    @Binding var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Menu {
                Picker(selection: $code) {
                    ForEach(SupportedCurrencies.all, id: \.self) { code in
                        Text(CurrencyNames.label(for: code)).tag(code)
                    }
                } label: {
                    EmptyView()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(CurrencyNames.symbol(for: code))
                        .font(.headline)
                        .foregroundStyle(Theme.brandInk)
                        .frame(width: 30, height: 30)
                        .background(Theme.brandTint, in: .rect(cornerRadius: 8))
                    Text(CurrencyNames.name(for: code))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .fieldSurface()
            }
            .accessibilityIdentifier("currency.picker")
        }
    }
}

enum CurrencyNames {
    /// "₪ שקל חדש" style label in Hebrew.
    static func label(for code: String) -> String {
        let locale = Locale(identifier: "he_IL")
        let name = locale.localizedString(forCurrencyCode: code) ?? code
        let symbol = symbol(for: code)
        return symbol == code ? "\(name) (\(code))" : "\(symbol) \(name)"
    }

    /// "שקל חדש", "דולר אמריקאי".
    static func name(for code: String) -> String {
        Locale(identifier: "he_IL").localizedString(forCurrencyCode: code) ?? code
    }

    private static var symbols: [String: String] = [:]

    /// "₪", "$", "€"; the code itself for currencies without a symbol.
    static func symbol(for code: String) -> String {
        if let cached = symbols[code] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "he_IL")
        formatter.currencyCode = code
        let symbol = formatter.currencySymbol ?? code
        symbols[code] = symbol
        return symbol
    }
}

extension CredentialsIssue {
    var message: LocalizedStringKey {
        switch self {
        case .fullNameMissing: "צריך למלא שם מלא"
        case .fullNameTooLong: "השם ארוך מדי"
        case .emailMissing: "צריך למלא אימייל"
        case .emailInvalid: "כתובת המייל לא תקינה"
        case .passwordMissing: "צריך למלא סיסמה"
        case .passwordTooShort: "הסיסמה צריכה לכלול לפחות 8 תווים"
        case .passwordNeedsLetterAndDigit: "הסיסמה צריכה לכלול אותיות באנגלית ומספרים"
        case .passwordsDontMatch: "הסיסמאות לא תואמות"
        case .termsNotAccepted: "צריך לאשר את תנאי השימוש ומדיניות הפרטיות"
        }
    }
}

extension AuthFailure {
    var message: LocalizedStringKey {
        switch self {
        case .invalidCredentials: "האימייל או הסיסמה לא נכונים"
        case .emailNotConfirmed: "צריך לאשר את כתובת המייל. בדקו את תיבת הדואר."
        case .emailAlreadyRegistered: "כבר קיים חשבון עם המייל הזה. אפשר להתחבר."
        case .weakPassword: "הסיסמה חלשה מדי. נסו סיסמה ארוכה יותר."
        case .rateLimited: "יותר מדי ניסיונות. נסו שוב בעוד כמה דקות."
        case .network: "אין חיבור לאינטרנט. בדקו את החיבור ונסו שוב."
        case .unknown: "משהו השתבש. נסו שוב."
        }
    }
}

/// Inline banner for a form-level error (e.g. wrong password).
struct ErrorBanner: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.expense)
        .padding(Spacing.m)
        .background(Theme.expenseTint, in: .rect(cornerRadius: Radius.control))
        .accessibilityIdentifier("form.error")
    }
}

/// Label for a primary button that shows a spinner while working.
struct LoadingLabel: View {
    let title: LocalizedStringKey
    let isLoading: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(Theme.onButtonPrimary)
            }
        }
    }
}

extension Color {
    /// "#RRGGBB" → Color. Invalid input gives the brand color.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 6, let value = UInt32(digits, radix: 16) {
            self.init(uiColor: UIColor(hex: value))
        } else {
            self = Theme.brand
        }
    }
}
