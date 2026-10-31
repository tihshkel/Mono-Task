import XCTest

@MainActor
final class CaptureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.monotask.capturepreview")
        app.launchArguments = ["--screenshots", "-monotask_task_layout", "list"]
        app.launch()
        XCTAssertTrue(app.buttons["workspace-folder-layout"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private var titleField: XCUIElement { app.textFields["task-capture-title"] }

    private func openCapture() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
    }

    private func openSidebar(_ title: String) {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.click()
    }

    func testWorkspaceShortcutPreservesDraftAndCancels() {
        openCapture()
        app.typeText("A draft from the keyboard")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(app.textFields.matching(identifier: "task-capture-title").count, 1)
        XCTAssertEqual(titleField.value as? String, "A draft from the keyboard")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(titleField.waitForNonExistence(timeout: 3))
        openCapture()
        app.typeText("A new draft")
        XCTAssertEqual(titleField.value as? String, "A new draft")
        app.buttons["Закрыть новое дело"].click()
        XCTAssertTrue(titleField.waitForNonExistence(timeout: 3))
    }

    func testFolderShortcutCreatesInCurrentFolder() {
        openSidebar("Учёба")
        openCapture()
        XCTAssertTrue(app.buttons["capture-folder-Учёба"].isSelected)
        app.typeText("A task in the current folder")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(titleField.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["A task in the current folder"].waitForExistence(timeout: 3))
        openSidebar("Проекты")
        XCTAssertFalse(app.buttons["A task in the current folder"].exists)
        openSidebar("Учёба")
        XCTAssertTrue(app.buttons["A task in the current folder"].exists)
    }

    func testPriorityShortcutKeepsPriority() {
        openSidebar("Приоритет")
        openCapture()
        app.typeText("A task with priority")
        app.buttons["task-capture-submit"].click()
        XCTAssertTrue(titleField.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["A task with priority"].waitForExistence(timeout: 3))
    }
}
