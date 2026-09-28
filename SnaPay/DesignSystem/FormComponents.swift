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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.s) {
                field
                    .font(.body)
                    .textInputAutocapitalization(kind == .name ? .words : .never)
                    .autocorrectionDisabled(kind != .name)
                    .keyboardType(kind == .email ? .emailAddress : .default)
                    .textContentType(contentType)
                    .accessibilityIdentifier(identifier)

                if kind.isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRevealed ? Text("הסתרת הסיסמה") : Text("הצגת הסיסמה"))
                    .accessibilityIdentifier("\(identifier).reveal")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(issue == nil ? Color.clear : Theme.expense, lineWidth: 1.5)
            }

            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.expense)
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
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isOn ? Theme.brand : (issue == nil ? Color.secondary : Theme.expense), lineWidth: 1.5)
                        .background(isOn ? Theme.brand : Color.clear, in: .rect(cornerRadius: 6))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
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
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.expense)
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
                .tint(Theme.brand)
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
            Text(draft.emoji)
                .font(.system(size: 30))
                .frame(width: 56, height: 56)
                .background(Color(hex: draft.colorHex).opacity(0.18), in: .rect(cornerRadius: 16))
            Text(draft.name)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .padding(Spacing.s)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isSelected ? Theme.brand : Color.clear, lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.brand)
                    .padding(6)
            }
        }
        .opacity(isSelected ? 1 : 0.6)
    }
}

/// Picker row for the user's main currency.
struct CurrencyPickerRow: View {
    let title: LocalizedStringKey
    @Binding var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Menu {
                Picker(selection: $code) {
                    ForEach(SupportedCurrencies.all, id: \.self) { code in
                        Text(CurrencyNames.label(for: code)).tag(code)
                    }
                } label: {
                    EmptyView()
                }
            } label: {
                HStack {
                    Text(CurrencyNames.label(for: code))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))
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

    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "he_IL")
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
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
        .background(Theme.expense.opacity(0.12), in: .rect(cornerRadius: Radius.control))
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
                ProgressView().tint(.white)
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
