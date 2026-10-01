import Foundation

/// A problem with what the user typed. The app maps each case to Hebrew copy.
public enum CredentialsIssue: Equatable, Sendable {
    case fullNameMissing
    case fullNameTooLong
    case emailMissing
    case emailInvalid
    case passwordMissing
    case passwordTooShort
    case passwordNeedsLetterAndDigit
    case passwordsDontMatch
    case termsNotAccepted
}

/// Field-level result so each text field can show its own error.
public struct CredentialsValidation: Equatable, Sendable {
    public var fullName: CredentialsIssue?
    public var email: CredentialsIssue?
    public var password: CredentialsIssue?
    public var passwordConfirmation: CredentialsIssue?
    public var terms: CredentialsIssue?

    public init() {}

    public var isValid: Bool {
        fullName == nil && email == nil && password == nil && passwordConfirmation == nil && terms == nil
    }
}

public enum CredentialsValidator {
    public static let minimumPasswordLength = 8
    public static let maximumNameLength = 80

    /// Validates the sign-up form. Firebase accepts any password of 6+ characters; the app asks for more:
    /// at least 8 characters with Latin letters and digits.
    public static func validateSignUp(
        fullName: String,
        email: String,
        password: String,
        passwordConfirmation: String,
        acceptedTerms: Bool
    ) -> CredentialsValidation {
        var result = CredentialsValidation()
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            result.fullName = .fullNameMissing
        } else if name.count > maximumNameLength {
            result.fullName = .fullNameTooLong
        }
        result.email = emailIssue(email)
        result.password = passwordIssue(password)
        if passwordConfirmation != password {
            result.passwordConfirmation = .passwordsDontMatch
        }
        if !acceptedTerms {
            result.terms = .termsNotAccepted
        }
        return result
    }

    /// Validates the log-in form. Only checks presence and email shape: the server decides
    /// whether the password is right, and old passwords may predate today's rules.
    public static func validateLogIn(email: String, password: String, acceptedTerms: Bool) -> CredentialsValidation {
        var result = CredentialsValidation()
        result.email = emailIssue(email)
        if password.isEmpty {
            result.password = .passwordMissing
        }
        if !acceptedTerms {
            result.terms = .termsNotAccepted
        }
        return result
    }

    /// Validates a new password (reset flow).
    public static func validateNewPassword(_ password: String, confirmation: String) -> CredentialsValidation {
        var result = CredentialsValidation()
        result.password = passwordIssue(password)
        if confirmation != password {
            result.passwordConfirmation = .passwordsDontMatch
        }
        return result
    }

    public static func emailIssue(_ email: String) -> CredentialsIssue? {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return .emailMissing }
        return isPlausibleEmail(value) ? nil : .emailInvalid
    }

    public static func passwordIssue(_ password: String) -> CredentialsIssue? {
        if password.isEmpty { return .passwordMissing }
        if password.count < minimumPasswordLength { return .passwordTooShort }
        // The server's "letters_digits" rule counts only Latin letters.
        let hasLetter = password.contains { $0.isASCII && $0.isLetter }
        let hasDigit = password.contains { $0.isASCII && $0.isNumber }
        return hasLetter && hasDigit ? nil : .passwordNeedsLetterAndDigit
    }

    /// Normalizes an email for sending to the server.
    public static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Deliberately loose: one "@", a non-empty local part, a domain with a dot and no spaces.
    /// The confirmation email is the real check.
    static func isPlausibleEmail(_ email: String) -> Bool {
        guard !email.contains(where: { $0.isWhitespace }) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."),
              dot != domain.startIndex,
              domain.index(after: dot) != domain.endIndex else { return false }
        return !domain.hasPrefix(".") && !domain.contains("..")
    }
}

public enum PersonName {
    /// First name for greetings ("דנה כהן" → "דנה"). Falls back to the whole trimmed name.
    public static func firstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
    }
}
