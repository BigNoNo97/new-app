import XCTest

/// Runs the onboarding flows against in-memory services (`-uiTesting`) and keeps screenshots
/// of every screen, in light and dark mode, as test attachments (exported by CI).
final class OnboardingUITests: XCTestCase {
    @MainActor
    func testSignUpThroughCategoriesToHome() {
        continueAfterFailure = false
        let app = launch()

        tap(app.buttons["welcome.start"], in: app)
        type("דנה כהן", into: app.textFields["signup.fullName"], in: app)
        type("dana@example.com", into: app.textFields["signup.email"], in: app)
        type("secret123", into: app.secureTextFields["signup.password"], in: app)
        type("secret123", into: app.secureTextFields["signup.confirmation"], in: app)
        tap(app.buttons["terms.checkbox"], in: app)
        tap(app.buttons["signup.submit"], in: app)

        let title = app.staticTexts["nice.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.label.contains("דנה"), "greets the user by first name")
        screenshot(app, "nice-to-meet-you-light")

        tap(app.buttons["nice.continue"], in: app)
        XCTAssertTrue(app.buttons["categories.tile.0"].waitForExistence(timeout: 10))
        screenshot(app, "categories-light")

        tap(app.buttons["categories.tile.0"], in: app)
        XCTAssertFalse(app.buttons["categories.tile.0"].isSelected, "tapping a tile deselects it")
        tap(app.buttons["categories.continue"], in: app)

        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        screenshot(app, "home-light")
    }

    @MainActor
    func testSignUpValidationAndSwitchToLogIn() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 10))
        screenshot(app, "welcome-light")

        tap(app.buttons["welcome.start"], in: app)
        XCTAssertTrue(app.buttons["signup.submit"].waitForExistence(timeout: 5))
        screenshot(app, "sign-up-light")

        type("secret", into: app.secureTextFields["signup.password"], in: app)
        tap(app.buttons["signup.submit"], in: app)
        XCTAssertTrue(app.staticTexts["signup.fullName.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["signup.password.error"].exists)
        screenshot(app, "sign-up-errors-light")

        tap(app.buttons["signup.password.reveal"], in: app)
        XCTAssertTrue(app.textFields["signup.password"].waitForExistence(timeout: 2), "eye button shows the password")

        tap(app.buttons["signup.toLogIn"], in: app)
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 5))
        screenshot(app, "log-in-light")
    }

    @MainActor
    func testLogInErrorAndForgotPassword() {
        continueAfterFailure = false
        let app = launch()

        tap(app.buttons["welcome.logIn"], in: app)
        type("wrong@example.com", into: app.textFields["login.email"], in: app)
        type("whatever1", into: app.secureTextFields["login.password"], in: app)
        tap(app.buttons["terms.checkbox"], in: app)
        tap(app.buttons["login.submit"], in: app)
        XCTAssertTrue(app.otherElements["form.error"].waitForExistence(timeout: 5)
            || app.staticTexts["form.error"].exists)
        screenshot(app, "log-in-error-light")

        tap(app.buttons["login.forgot"], in: app)
        XCTAssertTrue(app.buttons["forgot.send"].waitForExistence(timeout: 5))
        tap(app.buttons["forgot.send"], in: app)
        XCTAssertTrue(app.buttons["forgot.close"].waitForExistence(timeout: 5))
        screenshot(app, "forgot-password-sent-light")
    }

    @MainActor
    func testReturningUserLogsInToHome() {
        continueAfterFailure = false
        let app = launch()

        tap(app.buttons["welcome.logIn"], in: app)
        type("avi@example.com", into: app.textFields["login.email"], in: app)
        type("secret123", into: app.secureTextFields["login.password"], in: app)
        tap(app.buttons["terms.checkbox"], in: app)
        tap(app.buttons["login.submit"], in: app)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))

        tap(app.buttons["tab.profile"], in: app)
        tap(app.buttons["profile.signOut"], in: app)
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 10), "signing out returns to welcome")
    }

    @MainActor
    func testDarkModeScreens() {
        continueAfterFailure = false
        let app = launch(dark: true)
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 10))
        screenshot(app, "welcome-dark")

        tap(app.buttons["welcome.start"], in: app)
        tap(app.buttons["signup.submit"], in: app)
        XCTAssertTrue(app.staticTexts["signup.fullName.error"].waitForExistence(timeout: 5))
        screenshot(app, "sign-up-errors-dark")

        type("Avi Levi", into: app.textFields["signup.fullName"], in: app)
        type("avi@example.com", into: app.textFields["signup.email"], in: app)
        type("secret123", into: app.secureTextFields["signup.password"], in: app)
        type("secret123", into: app.secureTextFields["signup.confirmation"], in: app)
        tap(app.buttons["terms.checkbox"], in: app)
        tap(app.buttons["signup.submit"], in: app)
        XCTAssertTrue(app.staticTexts["nice.title"].waitForExistence(timeout: 10))
        screenshot(app, "nice-to-meet-you-dark")

        tap(app.buttons["nice.continue"], in: app)
        XCTAssertTrue(app.buttons["categories.tile.0"].waitForExistence(timeout: 10))
        screenshot(app, "categories-dark")
    }

    // MARK: Helpers

    @MainActor
    private func launch(dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (dark ? ["-uiTestingDark"] : [])
        app.launch()
        return app
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(element)", file: file, line: line)
        scrollIntoView(element, in: app)
        element.tap()
    }

    @MainActor
    private func type(_ text: String, into element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tap(element, in: app, file: file, line: line)
        element.typeText(text)
    }

    /// Scrolls until the element can be tapped (fields near the bottom sit under the keyboard).
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
