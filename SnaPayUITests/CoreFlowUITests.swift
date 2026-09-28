import XCTest

/// Stage 5 flows against in-memory services. Returning users are seeded with a few
/// transactions (see InMemoryServices.seed).
final class CoreFlowUITests: XCTestCase {
    @MainActor
    func testAddExpenseAppearsOnHome() {
        continueAfterFailure = false
        let app = launchSignedIn()
        screenshot(app, "home-light")

        addExpense(app, keys: ["4", "2", "dot", "5"], merchant: "רמי לוי", category: "סופר")

        XCTAssertTrue(app.buttons["transaction.רמי לוי"].waitForExistence(timeout: 10), "new expense shows on Home")
        screenshot(app, "home-after-add-light")

        tap(app.buttons["transaction.רמי לוי"], in: app)
        XCTAssertTrue(app.staticTexts["detail.amount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["detail.amount"].label.contains("42.5"))
        screenshot(app, "transaction-detail-light")
    }

    @MainActor
    func testForeignExpenseShowsConversion() {
        continueAfterFailure = false
        let app = launchSignedIn()

        tap(app.buttons["tab.add"], in: app)
        for key in ["2", "5"] { tap(app.buttons["key.\(key)"], in: app) }
        tap(app.buttons["add.currency"], in: app)
        let dollar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "דולר אמריקאי")).firstMatch
        tap(dollar, in: app)

        XCTAssertTrue(app.staticTexts["add.conversion"].waitForExistence(timeout: 5), "shows the amount in shekels")
        screenshot(app, "add-foreign-light")

        type("Amazon US", into: app.textFields["add.merchant"], in: app)
        tap(app.buttons["add.save"], in: app)
        tap(app.buttons["transaction.Amazon US"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["detail.conversion"].firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts["סה״כ בשקלים"].exists)
        screenshot(app, "transaction-detail-foreign-light")
    }

    @MainActor
    func testFilterExpensesByCategory() {
        continueAfterFailure = false
        let app = launchSignedIn()

        tap(app.buttons["tab.expenses"], in: app)
        XCTAssertTrue(app.textFields["expenses.search"].waitForExistence(timeout: 5))
        screenshot(app, "expenses-light")

        tap(app.buttons["expenses.filter"], in: app)
        tap(app.buttons["chip.🛒 סופר"], in: app)
        screenshot(app, "filters-light")
        tap(app.buttons["filter.apply"], in: app)

        XCTAssertTrue(app.descendants(matching: .any)["expenses.filteredTotal"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transaction.שופרסל דיל"].exists, "supermarket expense stays")
        XCTAssertFalse(app.buttons["transaction.ארומה"].exists, "coffee expense is filtered out")
        screenshot(app, "expenses-filtered-light")
    }

    @MainActor
    func testRecurringChargeIsCreated() {
        continueAfterFailure = false
        let app = launchSignedIn()

        tap(app.buttons["tab.add"], in: app)
        for key in ["4", "9"] { tap(app.buttons["key.\(key)"], in: app) }
        type("Netflix", into: app.textFields["add.merchant"], in: app)
        tap(app.buttons["add.details"], in: app)
        screenshot(app, "add-details-light")
        tap(app.descendants(matching: .any)["add.recurring"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["add.frequency.monthly"].waitForExistence(timeout: 5))
        screenshot(app, "add-recurring-light")
        tap(app.buttons["add.save"], in: app)

        XCTAssertTrue(app.buttons["transaction.Netflix"].waitForExistence(timeout: 10), "first occurrence is created today")
    }

    @MainActor
    func testTripMakesForeignCurrencyTheDefault() {
        continueAfterFailure = false
        let app = launchSignedIn()

        tap(app.buttons["tab.profile"], in: app)
        tap(app.buttons["profile.settings"], in: app)
        tap(app.buttons["profile.trips"], in: app)
        tap(app.buttons["trips.new"], in: app)
        type("ניו יורק", into: app.textFields["trip.name"], in: app)
        screenshot(app, "new-trip-light")
        tap(app.buttons["trip.save"], in: app)
        XCTAssertTrue(app.staticTexts["ניו יורק"].waitForExistence(timeout: 5))
        screenshot(app, "trips-light")
        app.buttons["סגירה"].firstMatch.tap()
        tap(app.buttons["settings.close"], in: app)

        tap(app.buttons["tab.home"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.trip"].firstMatch.waitForExistence(timeout: 5))

        tap(app.buttons["tab.add"], in: app)
        tap(app.buttons["key.9"], in: app)
        XCTAssertTrue(app.staticTexts["add.conversion"].waitForExistence(timeout: 5), "trip currency (USD) is the default")
    }

    @MainActor
    func testDarkModeCoreScreens() {
        continueAfterFailure = false
        let app = launchSignedIn(dark: true)
        screenshot(app, "home-dark")
        tap(app.buttons["tab.add"], in: app)
        for key in ["1", "2", "0"] { tap(app.buttons["key.\(key)"], in: app) }
        screenshot(app, "add-dark")
        app.buttons["ביטול"].firstMatch.tap()
        tap(app.buttons["tab.expenses"], in: app)
        XCTAssertTrue(app.textFields["expenses.search"].waitForExistence(timeout: 5))
        screenshot(app, "expenses-dark")
    }

    // MARK: Helpers

    @MainActor
    private func launchSignedIn(dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (dark ? ["-uiTestingDark"] : [])
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
    private func addExpense(_ app: XCUIApplication, keys: [String], merchant: String, category: String) {
        tap(app.buttons["tab.add"], in: app)
        for key in keys { tap(app.buttons["key.\(key)"], in: app) }
        tap(app.buttons["add.category.\(category)"], in: app)
        type(merchant, into: app.textFields["add.merchant"], in: app)
        screenshot(app, "add-light")
        tap(app.buttons["add.save"], in: app)
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
