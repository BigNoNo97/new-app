import XCTest

/// Stage 7: shared accounts. In-memory services simulate a partner, מיכל:
/// "invited@example.com" logs in with her pending invite, "shared@example.com" is already in
/// her household (see InMemoryServices).
final class FamilyUITests: XCTestCase {
    @MainActor
    func testAcceptInviteJoinsTheHousehold() {
        continueAfterFailure = false
        let app = launch(email: "invited@example.com")

        XCTAssertTrue(app.buttons["invite.accept"].waitForExistence(timeout: 10), "the invite is offered on arrival")
        screenshot(app, "invite-received-light")
        tap(app.buttons["invite.accept"], in: app)

        XCTAssertTrue(app.buttons["transaction.רמי לוי"].waitForExistence(timeout: 10), "the partner's expenses show up")
        XCTAssertTrue(app.buttons["transaction.ארומה"].exists, "my own expenses came along")
        screenshot(app, "home-shared-light")
    }

    @MainActor
    func testDeclineInvite() {
        continueAfterFailure = false
        let app = launch(email: "invited@example.com")

        tap(app.buttons["invite.decline"], in: app)
        XCTAssertTrue(waitForDisappearance(app.buttons["invite.accept"]))
        XCTAssertFalse(app.buttons["transaction.רמי לוי"].exists, "still a personal account")
    }

    @MainActor
    func testInvitePartnerFromSettings() {
        continueAfterFailure = false
        let app = launch(email: "shared@example.com")
        XCTAssertTrue(app.buttons["transaction.רמי לוי"].waitForExistence(timeout: 10))

        openSettings(app)
        XCTAssertTrue(app.descendants(matching: .any)["sharing.member.מיכל"].firstMatch.waitForExistence(timeout: 10),
                      "members are listed")
        type("dana@example.com", into: app.textFields["sharing.email"], in: app)
        tap(app.buttons["sharing.send"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["sharing.invite.dana@example.com"].firstMatch.waitForExistence(timeout: 5),
                      "the invite shows as pending")
        XCTAssertTrue(app.buttons["sharing.shareInvite"].exists, "the invite can be sent as a message")
        screenshot(app, "settings-sharing-light")

        // The same address twice explains itself.
        type("dana@example.com", into: app.textFields["sharing.email"], in: app)
        tap(app.buttons["sharing.send"], in: app)
        XCTAssertTrue(app.staticTexts["sharing.error"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLeaveSharedHousehold() {
        continueAfterFailure = false
        let app = launch(email: "shared@example.com")
        XCTAssertTrue(app.buttons["transaction.רמי לוי"].waitForExistence(timeout: 10))

        openSettings(app)
        tap(app.buttons["sharing.leave"], in: app)
        tap(app.buttons["יציאה"], in: app)

        XCTAssertTrue(app.staticTexts["חשבון אישי"].waitForExistence(timeout: 10), "back to a personal account")
        tap(app.buttons["tab.home"], in: app)
        XCTAssertTrue(app.buttons["transaction.ארומה"].waitForExistence(timeout: 10), "my expenses came with me")
        XCTAssertFalse(app.buttons["transaction.רמי לוי"].exists, "the partner's stayed behind")
    }

    @MainActor
    func testDarkModeFamilyScreens() {
        continueAfterFailure = false
        let app = launch(email: "shared@example.com", dark: true)
        XCTAssertTrue(app.buttons["transaction.רמי לוי"].waitForExistence(timeout: 10))
        screenshot(app, "home-shared-dark")
        openSettings(app)
        XCTAssertTrue(app.descendants(matching: .any)["sharing.member.מיכל"].firstMatch.waitForExistence(timeout: 10))
        screenshot(app, "settings-dark")
    }

    // MARK: Helpers

    @MainActor
    private func launch(email: String, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (dark ? ["-uiTestingDark"] : [])
        app.launch()
        tap(app.buttons["welcome.logIn"], in: app)
        type(email, into: app.textFields["login.email"], in: app)
        type("secret123", into: app.secureTextFields["login.password"], in: app)
        tap(app.buttons["terms.checkbox"], in: app)
        tap(app.buttons["login.submit"], in: app)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        tap(app.buttons["tab.profile"], in: app)
        tap(app.buttons["profile.settings"], in: app)
        XCTAssertTrue(app.buttons["settings.close"].waitForExistence(timeout: 5))
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
