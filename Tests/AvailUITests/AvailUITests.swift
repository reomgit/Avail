import XCTest

final class AvailUITests: XCTestCase {
    @MainActor
    func testFixtureLaunchesLibraryGridWithResumablePersistentPlayer() throws {
        let app = launchFixture()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["The Art of Listening"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("persistent-player-shell", in: app).exists)
        XCTAssertTrue(app.buttons["Resume"].exists)
    }

    @MainActor
    func testGridDetailAndBackKeepThePlayerMounted() throws {
        let app = launchFixture()

        let book = app.buttons["The Art of Listening"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.click()

        XCTAssertTrue(app.staticTexts["Chapters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Listen"].exists || app.buttons["Continue"].exists)
        XCTAssertTrue(app.buttons["Resume"].exists)

        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.click()

        XCTAssertTrue(app.buttons["The Art of Listening"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Resume"].exists)
    }

    @MainActor
    func testCompactWindowChoosesCompactPlayerArrangement() throws {
        let app = launchFixture(compact: true)

        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["Book position"].exists)
        XCTAssertTrue(element("persistent-player-shell", in: app).exists)
    }

    @MainActor
    func testZenOpensAsASeparateWindowAndClosingItKeepsMainPlayer() throws {
        let app = launchFixture()
        let book = app.buttons["The Art of Listening"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.click()
        XCTAssertTrue(app.staticTexts["Chapters"].waitForExistence(timeout: 5))

        app.buttons["Open Zen"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { app.windows.count == 2 })

        let zenWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(zenWindow.buttons["Hide Inspector"].waitForExistence(timeout: 5))
        zenWindow.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) { app.windows.count == 1 })
        XCTAssertTrue(app.buttons["Resume"].exists)
    }

    @MainActor
    private func launchFixture(compact: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-UITesting",
            "-ApplePersistenceIgnoreState",
            "YES",
        ]
        if compact { app.launchArguments.append("-UITestCompact") }
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 1) {
            app.activate()
            app.typeKey("n", modifierFlags: .command)
        }
        return app
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
