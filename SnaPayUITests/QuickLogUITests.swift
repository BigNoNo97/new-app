import XCTest

/// Stage 6: quick-log from Apple Pay. The Shortcuts card itself can't run in UI tests; these
/// cover what the app shows around it. `-uiTestingQuickLog` starts with one captured payment
/// ("קפה לנדוור") waiting for a category.
final class QuickLogUITests: XCTestCase {
    @MainActor
    func testPendingPaymentIsFiledFromHome() {
        continueAfterFailure = false
        let app = launchSignedIn(seedPayment: true)

        XCTAssertTrue(app.descendants(matching: .any)["pending.card"].firstMatch.waitForExistence(timeout: 10), "captured payment waits on Home")
        XCTAssertFalse(app.descendants(matching: .any)["quicklog.setupCard"].firstMatch.exists, "setup card hides once a payment arrived")
        screenshot(app, "home-pending-light")

        // "קפה לנדוור" is a coffee shop: the coffee category is picked for the user.
        XCTAssertTrue(app.staticTexts["מוצע: ☕ קפה"].waitForExistence(timeout: 5), "Home shows the category picked for the user")
        tap(app.buttons["pending.choose"], in: app)
        XCTAssertTrue(app.buttons["pending.category.קפה"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pending.category.קפה"].firstMatch.isSelected, "the picked category is preselected")
        let note = app.textFields["pending.note"]
        tap(note, in: app)
        note.typeText("Dana")
        screenshot(app, "pending-categories-light")
        tap(app.buttons["pending.save"], in: app)

        XCTAssertTrue(app.buttons["transaction.קפה לנדוור"].waitForExistence(timeout: 10), "filed payment becomes a transaction")
        XCTAssertTrue(waitForDisappearance(app.descendants(matching: .any)["pending.card"].firstMatch), "nothing left to file")
    }

    @MainActor
    func testDiscardPendingPayment() {
        continueAfterFailure = false
        let app = launchSignedIn(seedPayment: true)

        tap(app.buttons["pending.choose"], in: app)
        tap(app.buttons["pending.discard"], in: app)

        XCTAssertTrue(waitForDisappearance(app.descendants(matching: .any)["pending.card"].firstMatch))
        XCTAssertFalse(app.buttons["transaction.קפה לנדוור"].exists)
    }

    @MainActor
    func testSetupGuideAndToggle() {
        continueAfterFailure = false
        let app = launchSignedIn(seedPayment: false)

        XCTAssertTrue(app.descendants(matching: .any)["quicklog.setupCard"].firstMatch.waitForExistence(timeout: 10), "Home invites to set up quick-log")
        tap(app.buttons["quicklog.setupCard.open"], in: app)
        // The main button adds the ready-made shortcut first when there is one, then opens Shortcuts.
        let addShortcut = app.buttons["quicklog.addShortcut"]
        let openShortcuts = app.buttons["quicklog.openShortcuts"]
        XCTAssertTrue(addShortcut.waitForExistence(timeout: 5) || openShortcuts.exists, "guide opens on the steps")
        screenshot(app, "quicklog-setup-light")
        tap(app.buttons["quicklog.alreadySet"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["quicklog.status.waiting"].firstMatch.waitForExistence(timeout: 5), "waits for the first payment")
        screenshot(app, "quicklog-setupwait-light")
        app.buttons["סגירה"].firstMatch.tap()

        tap(app.buttons["tab.profile"], in: app)
        tap(app.buttons["profile.settings"], in: app)
        let toggle = app.descendants(matching: .any)["profile.quickLog"].firstMatch
        tap(toggle, in: app)
        screenshot(app, "settings-quicklog-off-light")
        tap(app.buttons["settings.close"], in: app)

        tap(app.buttons["tab.home"], in: app)
        XCTAssertTrue(waitForDisappearance(app.descendants(matching: .any)["quicklog.setupCard"].firstMatch), "no invitation while quick-log is off")
    }

    @MainActor
    func testDarkModeQuickLogScreens() {
        continueAfterFailure = false
        let app = launchSignedIn(seedPayment: true, dark: true)
        XCTAssertTrue(app.descendants(matching: .any)["pending.card"].firstMatch.waitForExistence(timeout: 10))
        screenshot(app, "home-pending-dark")

        tap(app.buttons["tab.profile"], in: app)
        tap(app.buttons["profile.settings"], in: app)
        tap(app.buttons["profile.quickLogSetup"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["quicklog.status"].firstMatch.waitForExistence(timeout: 5), "shows that the first payment arrived")
        screenshot(app, "quicklog-setup-works-dark")
    }

    // MARK: Helpers

    @MainActor
    private func launchSignedIn(seedPayment: Bool, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (seedPayment ? ["-uiTestingQuickLog"] : []) + (dark ? ["-uiTestingDark"] : [])
        app.launch()
        tap(app.buttons["welcome.logIn"], in: app)
        type("returning@example.com", into: app.textFields["login.email"], in: app)
        type("secret123", into: app.secureTextFields["login.password"], in: app)
        tap(app.buttons["terms.checkbox"], in: app)
        tap(app.buttons["login.submit"], in: app)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["home.totalSpent"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(element)", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }

    @MainActor
    private func type(_ text: String, into element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tap(element, in: app, file: file, line: line)
        element.typeText(text)
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
