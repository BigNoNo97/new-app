import Testing
@testable import SnaPayCore

struct CredentialsValidatorTests {
    @Test func validSignUp() {
        let result = CredentialsValidator.validateSignUp(
            fullName: "דנה כהן", email: "dana@example.com",
            password: "secret123", passwordConfirmation: "secret123", acceptedTerms: true
        )
        #expect(result.isValid)
    }

    @Test func signUpReportsEachField() {
        let result = CredentialsValidator.validateSignUp(
            fullName: "  ", email: "dana@", password: "short1",
            passwordConfirmation: "other", acceptedTerms: false
        )
        #expect(result.fullName == .fullNameMissing)
        #expect(result.email == .emailInvalid)
        #expect(result.password == .passwordTooShort)
        #expect(result.passwordConfirmation == .passwordsDontMatch)
        #expect(result.terms == .termsNotAccepted)
        #expect(!result.isValid)
    }

    @Test(arguments: [
        ("", CredentialsIssue.passwordMissing),
        ("abc123", .passwordTooShort),
        ("abcdefgh", .passwordNeedsLetterAndDigit),
        ("12345678", .passwordNeedsLetterAndDigit),
        ("סיסמהטובה1", .passwordNeedsLetterAndDigit),
        ("סיסמהטובהA1", nil),
        ("abcdefg1", nil),
    ] as [(String, CredentialsIssue?)])
    func passwordRules(password: String, expected: CredentialsIssue?) {
        #expect(CredentialsValidator.passwordIssue(password) == expected)
    }

    @Test(arguments: [
        ("dana@example.com", nil),
        ("  dana@example.co.il ", nil),
        ("", CredentialsIssue.emailMissing),
        ("dana", .emailInvalid),
        ("dana@example", .emailInvalid),
        ("@example.com", .emailInvalid),
        ("dana@@example.com", .emailInvalid),
        ("da na@example.com", .emailInvalid),
        ("dana@example.", .emailInvalid),
        ("dana@.example.com", .emailInvalid),
    ] as [(String, CredentialsIssue?)])
    func emailRules(email: String, expected: CredentialsIssue?) {
        #expect(CredentialsValidator.emailIssue(email) == expected)
    }

    @Test func logInDoesNotApplyPasswordRules() {
        let result = CredentialsValidator.validateLogIn(email: "a@b.co", password: "x", acceptedTerms: true)
        #expect(result.isValid)
    }

    @Test func logInRequiresTerms() {
        let result = CredentialsValidator.validateLogIn(email: "a@b.co", password: "x", acceptedTerms: false)
        #expect(result.terms == .termsNotAccepted)
    }

    @Test func newPassword() {
        #expect(CredentialsValidator.validateNewPassword("secret123", confirmation: "secret123").isValid)
        #expect(CredentialsValidator.validateNewPassword("secret123", confirmation: "secret124").passwordConfirmation == .passwordsDontMatch)
    }

    @Test func normalizesEmail() {
        #expect(CredentialsValidator.normalizedEmail("  Dana@Example.COM ") == "dana@example.com")
    }

    @Test func firstName() {
        #expect(PersonName.firstName(from: "  דנה   כהן ") == "דנה")
        #expect(PersonName.firstName(from: "Avi") == "Avi")
        #expect(PersonName.firstName(from: "   ") == "")
    }
}

struct DefaultCategoriesTests {
    @Test func defaultsAreValidAndUnique() {
        let all = DefaultCategories.expenses + DefaultCategories.income
        #expect(all.allSatisfy(DefaultCategories.isValid))
        #expect(Set(DefaultCategories.expenses.map(\.name)).count == DefaultCategories.expenses.count)
        #expect(DefaultCategories.expenses.count == 16)
        #expect(DefaultCategories.income.allSatisfy { $0.kind == .income })
    }

    @Test func rejectsInvalidDrafts() {
        #expect(!DefaultCategories.isValid(CategoryDraft(name: " ", emoji: "🍔", colorHex: "#FFFFFF")))
        #expect(!DefaultCategories.isValid(CategoryDraft(name: "אוכל", emoji: "", colorHex: "#FFFFFF")))
        #expect(!DefaultCategories.isValid(CategoryDraft(name: "אוכל", emoji: "🍔", colorHex: "red")))
    }

    @Test func paletteColorsAreHex() {
        #expect(DefaultCategories.palette.allSatisfy {
            $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        })
    }
}
