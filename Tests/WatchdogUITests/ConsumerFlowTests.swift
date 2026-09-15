import XCTest

/// Runs entirely against explicitly fictional records. Apple Maps tiles may use the network;
/// parcel research never calls a production service with these launch arguments.
final class ConsumerFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--sample-data", "--reset-library"]
        app.launch()
        XCTAssertTrue(app.textFields["explorer.searchField"].waitForExistence(timeout: 15))
    }

    func testFreeSearchAndSavedPropertySurviveRelaunch() {
        search("Lantern")
        openFirstSample()
        let save = app.buttons["dossier.save"]
        reveal(save)
        save.tap()
        XCTAssertTrue(save.label.contains("Saved"))
        screenshot("iOS property dossier")
        app.buttons["dossier.done"].tap()
        navigate("Saved")
        XCTAssertTrue(app.staticTexts["24 Lantern Lane"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--sample-data"]
        app.launch()
        navigate("Saved")
        XCTAssertTrue(app.staticTexts["24 Lantern Lane"].waitForExistence(timeout: 5))
    }

    func testPrivateNotePersistsBetweenPropertyVisits() {
        search("Lantern")
        openFirstSample()
        let sections = app.segmentedControls["dossier.section"]
        reveal(sections)
        sections.buttons["Notes"].tap()
        let note = app.textViews["dossier.note"]
        reveal(note)
        note.tap()
        note.typeText("Check the municipal tax year.")
        app.buttons["dossier.done"].tap()
        openFirstSample()
        reveal(sections)
        sections.buttons["Notes"].tap()
        reveal(note)
        XCTAssertEqual(note.value as? String, "Check the municipal tax year.")
    }

    func testAssessmentFilterChangesResultsAndCanBeCleared() {
        search("Haddonfield")
        XCTAssertTrue(app.buttons["explorer.record.sample-1"].waitForExistence(timeout: 5))
        let filter = app.buttons["explorer.filters"]
        reveal(filter)
        filter.tap()
        let maximum = app.textFields["explorer.filters.maximum"]
        XCTAssertTrue(maximum.waitForExistence(timeout: 5))
        maximum.tap()
        maximum.typeText("400000")
        let apply = app.buttons["explorer.filters.apply"]
        if !apply.isHittable, app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        apply.tap()
        XCTAssertTrue(app.staticTexts["Give your search more room"].waitForExistence(timeout: 5))
        let clear = app.buttons["Clear filters"]
        reveal(clear)
        clear.tap()
        XCTAssertTrue(app.buttons["explorer.record.sample-1"].waitForExistence(timeout: 5))
    }

    func testTownsAndConsumerNavigation() {
        screenshot("iOS Explore")
        navigate("Towns")
        let townSearch = app.searchFields.firstMatch
        XCTAssertTrue(townSearch.waitForExistence(timeout: 5))
        townSearch.tap()
        townSearch.typeText("Haddonfield\n")
        XCTAssertTrue(app.staticTexts["Haddonfield"].firstMatch.waitForExistence(timeout: 5))
        screenshot("iOS Towns")
        navigate("My Watchdog")
        XCTAssertTrue(app.buttons["global.settings"].waitForExistence(timeout: 5))
        app.buttons["global.settings"].tap()
        XCTAssertTrue(app.staticTexts["Your research. Your space."].waitForExistence(timeout: 5))
    }

    private func search(_ text: String) {
        let field = app.textFields["explorer.searchField"]
        field.tap()
        field.typeText(text + "\n")
    }
    private func openFirstSample() {
        let row = app.buttons["explorer.record.sample-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        reveal(row)
        row.tap()
        XCTAssertTrue(app.buttons["dossier.done"].waitForExistence(timeout: 5))
    }
    private func navigate(_ title: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap(); return }
        let sidebar = app.buttons[title].firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected accessible control: \(element)")
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
