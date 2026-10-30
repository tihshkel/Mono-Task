import XCTest

@MainActor
final class WorkspaceSharingTests: XCTestCase {
    private let folderID = "workspace-shared-folder-33333333-3333-3333-3333-333333333333"

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--shared-preview"]
        app.launch()
        XCTAssertTrue(app.buttons[folderID].waitForExistence(timeout: 10))
        return app
    }

    func testSharedFolderShowsMembersAndOpensTasks() {
        let app = launch()
        let folder = app.buttons[folderID]
        XCTAssertTrue(folder.label.contains("Вы"))
        XCTAssertTrue(folder.label.contains("Саша"))
        folder.tap()
        XCTAssertTrue(app.buttons["shared-add-task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Подготовить общий план"].exists)
        app.buttons["shared-manage-members"].tap()
        XCTAssertTrue(app.staticTexts["Саша"].waitForExistence(timeout: 4))
    }

    func testCreatedSharedFolderAppearsAutomatically() {
        let app = launch()
        app.buttons["workspace-shared-folders"].tap()
        XCTAssertTrue(app.buttons["shared-create-list"].waitForExistence(timeout: 5))
        app.buttons["shared-create-list"].tap()
        let name = app.textFields["shared-folder-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        name.tap()
        name.typeText("Командная папка")
        app.swipeUp()
        app.buttons["shared-confirm-create"].tap()
        XCTAssertTrue(app.images["shared-invite-qr"].waitForExistence(timeout: 5))
        app.buttons["shared-open-created-folder"].tap()
        XCTAssertTrue(app.buttons["shared-add-task"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Закрыть"].tap()
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Общая папка Командная папка'"))
            .firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        let search = app.textFields["Поиск задач и папок"]
        search.tap()
        search.typeText("Командная")
        XCTAssertTrue(folder.exists)
        XCTAssertFalse(app.buttons[folderID].exists)
    }

    func testProfileAndThemePreviews() {
        let app = launch()
        app.buttons["navigation-settings"].tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-account"].label.contains("Мой профиль"))
        app.buttons["settings-account"].tap()
        XCTAssertTrue(app.buttons["Синхронизировать сейчас"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let appearance = app.descendants(matching: .any)
            .matching(identifier: "settings-page-list.bullet.rectangle").firstMatch
        app.swipeUp()
        appearance.tap()
        XCTAssertTrue(app.staticTexts["Оформление пространства"].waitForExistence(timeout: 5))
        let dark = app.segmentedControls.buttons["Тёмная"]
        let light = app.segmentedControls.buttons["Светлая"]
        let system = app.segmentedControls.buttons["Системная"]
        let original = dark.isSelected ? "Тёмная" : system.isSelected ? "Системная" : "Светлая"
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        light.tap()
        XCTAssertTrue(light.isSelected)
        app.segmentedControls.buttons[original].tap()
    }
}

@MainActor
final class ReviewTests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.staticTexts["СЕГОДНЯ"].waitForExistence(timeout: 10))
    }
    func testSectionTitlesAlignAndAnalyticsHasNoSyncStatus() {
        let todayY = app.staticTexts["СЕГОДНЯ"].frame.minY
        app.buttons["navigation-activity"].tap()
        let activity = app.staticTexts["АНАЛИТИКА"]
        XCTAssertTrue(activity.waitForExistence(timeout: 3))
        XCTAssertEqual(activity.frame.minY, todayY, accuracy: 1)
        XCTAssertFalse(app.buttons["sync-status"].isHittable)
        app.buttons["navigation-settings"].tap()
        let settings = app.staticTexts["НАСТРОЙКИ"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(settings.frame.minY, todayY, accuracy: 1)
    }

    func testCompletionAndFilters() {
        XCTAssertEqual(app.staticTexts["focus-completion-count"].label, "1")
        app.buttons.matching(identifier: "Отметить выполненной").firstMatch.tap()
        let updated = NSPredicate(format: "label == '2'")
        expectation(for: updated, evaluatedWith: app.staticTexts["focus-completion-count"])
        waitForExpectations(timeout: 4)
        app.buttons["task-scope-all"].tap()
        XCTAssertTrue(app.staticTexts["/ 7 ГОТОВО"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'task-scope-' AND label BEGINSWITH 'УЧЁБА'"))
            .firstMatch.tap()
        XCTAssertTrue(app.staticTexts["/ 3 ГОТОВО"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Закончить макет приложения"].exists)
    }
    func testSettingsAndSchedule() {
        app.buttons["navigation-settings"].tap()
        app.staticTexts["Категории и расписание"].tap()
        app.buttons.containing(.staticText, identifier: "Учёба").firstMatch.tap()
        XCTAssertTrue(app.buttons["Сохранить"].waitForExistence(timeout: 3))
        app.buttons["ПН"].tap()
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["Вт, Ср, Чт, Пт, Сб, Вс"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Каждый день"].exists)
    }
    func testAnalyticsAndDayDetails() {
        app.buttons["navigation-activity"].tap()
        XCTAssertTrue(app.staticTexts["По дням недели"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Неделя"].tap()
        XCTAssertTrue(app.staticTexts["1"].exists)
        app.segmentedControls.buttons["Год"].tap()
        XCTAssertTrue(app.staticTexts["октябрь"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Месяц"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'выполнено'")).firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Выполнено:'")).firstMatch.waitForExistence(
                timeout: 3))
    }
    func testSyncDetailsAndCapture() {
        app.buttons["sync-status"].tap()
        XCTAssertTrue(app.buttons["Синхронизировать сейчас"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Синхронизировать сейчас"].isEnabled)
        app.buttons["Закрыть"].tap()
        app.buttons["navigation-add-task"].tap()
        let field = app.textFields["Новая задача"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Review smoke task")
        app.keyboards.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Review smoke task"].waitForExistence(timeout: 3))
    }
}

@MainActor
final class MotionAndRefreshTests: XCTestCase {
    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots"] + args
        app.launch()
        XCTAssertTrue(app.staticTexts["СЕГОДНЯ"].waitForExistence(timeout: 10))
        return app
    }

    func testKeyboardCollapsesAndRestoresHeader() {
        let app = launch()
        let title = app.staticTexts["СЕГОДНЯ"]
        let before = title.frame
        let field = app.textFields["Новая задача"]
        app.buttons["navigation-add-task"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        for index in 0..<3 {
            field.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Скрыть клавиатуру"].waitForExistence(timeout: 3))
            XCTAssertLessThan(title.frame.height, before.height - 5)
            XCTAssertFalse(app.staticTexts["focus-completion-count"].isHittable)
            XCTAssertLessThan(field.frame.maxY, app.frame.height - 200)
            if index == 0 {
                field.typeText("Motion")
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "KeyboardOpen"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertEqual(field.value as? String, "Motion")
            app.buttons["Скрыть клавиатуру"].tap()
            XCTAssertTrue(app.staticTexts["focus-completion-count"].waitForExistence(timeout: 3))
            XCTAssertEqual(title.frame.height, before.height, accuracy: 1)
            XCTAssertTrue(app.buttons["Закрыть ввод"].isHittable)
        }
        XCTAssertEqual(title.frame.minY, before.minY, accuracy: 1)
    }

    func testRefreshCompletesAfterViewUpdates() {
        let app = launch(["--sync-preview"])
        let scroll = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }!
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
        let success = NSPredicate(format: "label CONTAINS 'СИНХРОНИЗИРОВАНО'")
        expectation(for: success, evaluatedWith: app.buttons["sync-status"])
        waitForExpectations(timeout: 6)
    }

    func testCancelledCallerDoesNotCancelSync() {
        let app = launch(["--sync-preview", "--cancel-sync-request"])
        let success = NSPredicate(format: "label CONTAINS 'СИНХРОНИЗИРОВАНО'")
        expectation(for: success, evaluatedWith: app.buttons["sync-status"])
        waitForExpectations(timeout: 6)
    }

    func testSyncPanelHasCompactHeightAndReadableButton() {
        let app = launch()
        app.buttons["sync-status"].tap()
        let button = app.buttons["Синхронизировать сейчас"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        // Check the usable target in screen coordinates; sheet presentation can
        // scale the 52 pt content slightly while its animation settles.
        XCTAssertGreaterThanOrEqual(button.frame.height, 48)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "CompactSyncPanel"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(app.buttons["Закрыть"].frame.minY, app.frame.height * 0.55)
    }
}

@MainActor
final class SettingsOverviewTests: XCTestCase {
    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.staticTexts["СЕГОДНЯ"].waitForExistence(timeout: 10))
        app.buttons["navigation-settings"].tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 3))
        return app
    }

    func testAccountAndSchedulePreviewOpenTheirDetails() {
        let app = openSettings()
        XCTAssertFalse(app.images["person.crop.circle"].exists)
        app.buttons["settings-account"].tap()
        XCTAssertTrue(app.buttons["Синхронизировать сейчас"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settings-preview-'"))
            .firstMatch.tap()
        XCTAssertTrue(app.buttons["Сохранить"].waitForExistence(timeout: 3))
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 3))
        app.staticTexts["Уведомления"].tap()
        XCTAssertTrue(app.switches["Уведомления MonoTask"].waitForExistence(timeout: 3))
    }

    func testAppearanceSummaryTracksPreferences() {
        let app = openSettings()
        app.staticTexts["Вид списка задач"].tap()
        let toggle = app.switches["Компактные строки задач"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let wasCompact = toggle.value as? String == "1"
        toggle.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let expected = wasCompact ? "Обычные строки" : "Компактные строки"
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", expected))
                .firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Вид списка задач"].tap()
        toggle.tap()
        app.navigationBars.buttons.firstMatch.tap()
    }
}

@MainActor
final class SettingsClarityTests: XCTestCase {
    func testListPreviewAndRemovedHeading() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--settings"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'под ваш ритм'")).firstMatch.exists)
        app.staticTexts["Вид списка задач"].tap()
        XCTAssertTrue(app.staticTexts["settings-preview-task"].waitForExistence(timeout: 3))
        let notes = app.switches["Показывать заметки в списке"]
        let wasOn = notes.value as? String == "1"
        notes.tap()
        XCTAssertEqual(app.staticTexts["settings-preview-notes"].exists, !wasOn)
        notes.tap()
    }

    func testSignOutButtonOpensConfirmationAndCanBeCancelled() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--settings", "--settings-sync", "--sync-success"]
        app.launch()
        let button = app.buttons["settings-sign-out"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(button.frame.height, 48)
        button.tap()
        XCTAssertTrue(app.buttons["Выйти"].waitForExistence(timeout: 3))
        let cancel = app.buttons.matching(NSPredicate(format: "label IN {'Отмена', 'Cancel'}")).firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)).tap()
        }
        XCTAssertFalse(app.buttons["Выйти"].exists)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
    }
}

@MainActor
final class FloatingNavigationTests: XCTestCase {
    func testGlassEdgesAndContentUnderPanel() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--scroll-gesture-test"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation-add-task"].waitForExistence(timeout: 8))
        app.buttons["task-scope-all"].tap()
        app.swipeUp()
        let scroll = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }!
        XCTAssertGreaterThanOrEqual(scroll.frame.maxY, app.frame.maxY - 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ContentBehindGlass"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["navigation-today"].press(forDuration: 1.5)
        app.buttons["navigation-activity"].tap()
        XCTAssertTrue(app.buttons["navigation-add-task"].isHittable)
        app.buttons["navigation-activity"].press(forDuration: 1.5)
        let analytics = XCTAttachment(screenshot: app.screenshot())
        analytics.name = "AnalyticsGlass"
        analytics.lifetime = .keepAlways
        add(analytics)
    }

    func testUndoGlassToastDoesNotShortenList() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--scroll-gesture-test"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation-add-task"].waitForExistence(timeout: 8))
        app.buttons["task-scope-all"].tap()
        let task = app.staticTexts["Тест прокрутки · 1"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.swipeLeft()
        let delete = app.buttons["УДАЛИТЬ"].firstMatch
        if delete.waitForExistence(timeout: 1) { delete.tap() }
        let undo = app.buttons["Отменить удаление"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["navigation-add-task"].isHittable)
        let scroll = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }!
        XCTAssertGreaterThanOrEqual(scroll.frame.maxY, app.frame.maxY - 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "GlassUndoToast"
        shot.lifetime = .keepAlways
        add(shot)
        undo.tap()
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertFalse(undo.exists)
    }

    func testNavigationAndAddFromAnotherSection() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        let add = app.buttons["navigation-add-task"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(add.frame.width, 44)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        for section in ["activity", "settings"] {
            let tab = app.buttons["navigation-\(section)"]
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
            tab.tap()
            XCTAssertTrue(add.isHittable)
        }
        add.tap()
        let field = app.textFields["Новая задача"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "ExpandedGlassInput"
        expanded.lifetime = .keepAlways
        self.add(expanded)
        field.tap()
        XCTAssertTrue(app.buttons["Скрыть клавиатуру"].waitForExistence(timeout: 4))
        let keyboard = XCTAttachment(screenshot: app.screenshot())
        keyboard.name = "GlassInputAboveKeyboard"
        keyboard.lifetime = .keepAlways
        self.add(keyboard)
        field.typeText("Navigation task")
        app.keyboards.buttons["Done"].tap()
        if app.buttons["Скрыть клавиатуру"].exists { app.buttons["Скрыть клавиатуру"].tap() }
        app.buttons["task-scope-all"].tap()
        XCTAssertTrue(app.staticTexts["Navigation task"].waitForExistence(timeout: 4))
        app.buttons["Закрыть ввод"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
    }
}

@MainActor
final class TaskEditingTests: XCTestCase {
    func testNotesAndSubtasksSurviveClosingEditor() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation-add-task"].waitForExistence(timeout: 8))
        app.buttons["navigation-add-task"].tap()
        let input = app.textFields["Новая задача"]
        input.tap()
        input.typeText("Release review")
        app.keyboards.buttons["Done"].tap()
        if app.buttons["Скрыть клавиатуру"].exists { app.buttons["Скрыть клавиатуру"].tap() }
        app.buttons["Закрыть ввод"].tap()
        app.buttons["task-scope-all"].tap()
        let task = app.staticTexts["Release review"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
        let notes = app.descendants(matching: .any).matching(identifier: "task-editor-notes").firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        notes.tap()
        notes.typeText("Release notes")
        let addSubtask = app.textFields["task-editor-add-subtask"]
        if !addSubtask.isHittable { app.swipeUp() }
        addSubtask.tap()
        addSubtask.typeText("Verify release\n")
        app.buttons["Готово"].tap()
        task.tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        XCTAssertEqual(notes.value as? String, "Release notes")
        let subtask = app.textFields["Подзадача"].firstMatch
        if !subtask.isHittable { app.swipeUp() }
        XCTAssertTrue(subtask.waitForExistence(timeout: 3))
        XCTAssertEqual(subtask.value as? String, "Verify release")
        app.buttons["Готово"].tap()
    }

    func testCreateCategoryAndSchedule() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--settings", "--settings-categories"]
        app.launch()
        let create = app.buttons["Новая категория"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let name = app.textFields["Название"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Сохранить"].isEnabled)
        name.tap()
        name.typeText("Release category")
        app.buttons["ПН"].tap()
        app.buttons["Сохранить"].tap()
        let category = app.buttons.containing(.staticText, identifier: "Release category").firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        category.tap()
        XCTAssertEqual(name.value as? String, "Release category")
        app.buttons["Отмена"].tap()
    }
}

@MainActor
final class SharedListUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--shared-preview", "--settings"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-shared-lists"].waitForExistence(timeout: 10))
        app.buttons["settings-shared-lists"].tap()
        XCTAssertTrue(app.buttons["shared-create-list"].waitForExistence(timeout: 5))
        return app
    }

    func testSharedTaskNotesSubtaskAndCompletion() {
        let app = launch()
        app.buttons["shared-list-33333333-3333-3333-3333-333333333333"].tap()
        app.buttons["shared-add-task"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "shared-task-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["shared-save-task"].isEnabled)
        title.tap()
        title.typeText("Совместная проверка")
        let notes = app.descendants(matching: .any).matching(identifier: "shared-task-notes").firstMatch
        notes.tap()
        notes.typeText("Общие заметки")
        let subtask = app.textFields["shared-subtask-input"]
        if !subtask.isHittable { app.swipeUp() }
        subtask.tap()
        subtask.typeText("Первый шаг")
        app.buttons["Добавить"].tap()
        app.buttons["shared-save-task"].tap()
        let task = app.staticTexts["Совместная проверка"]
        XCTAssertTrue(task.waitForExistence(timeout: 4))
        task.tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 4))
        XCTAssertEqual(notes.value as? String, "Общие заметки")
        XCTAssertEqual(app.textFields["Подзадача"].firstMatch.value as? String, "Первый шаг")
        let done = app.switches["Выполнено"]
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(done.value as? String, "1")
        app.buttons["shared-save-task"].tap()
        XCTAssertTrue(app.staticTexts["1 / 2 выполнено"].waitForExistence(timeout: 4))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "SharedListTasks"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testOwnerCanCreateInviteAndRemoveParticipant() {
        let app = launch()
        app.buttons["shared-list-33333333-3333-3333-3333-333333333333"].tap()
        app.buttons["shared-manage-members"].tap()
        XCTAssertTrue(app.staticTexts["Саша"].waitForExistence(timeout: 4))
        app.buttons["shared-open-invite"].tap()
        XCTAssertTrue(app.images["shared-invite-qr"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["Код для ручного ввода"].tap()
        XCTAssertTrue(app.staticTexts["shared-generated-code"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["shared-generated-code"].label.count, 32)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "SharedListInvitation"
        shot.lifetime = .keepAlways
        add(shot)
        app.navigationBars.buttons["Готово"].firstMatch.tap()
        app.buttons["Удалить"].tap()
        app.buttons["Подтвердить"].tap()
        let removed = app.descendants(matching: .any).matching(
            identifier: "shared-member-22222222-2222-2222-2222-222222222222"
        ).firstMatch
        XCTAssertTrue(removed.waitForNonExistence(timeout: 5))
    }

    func testLiveHTTPSInvitationOpensApp() throws {
        guard ProcessInfo.processInfo.environment["MONOTASK_TEST_LIVE_INVITE"] == "1" else {
            throw XCTSkip("Requires the published invitation page; enable MONOTASK_TEST_LIVE_INVITE=1")
        }
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--shared-preview"]
        app.launch()
        XCTAssertTrue(
            app.buttons["workspace-shared-folder-33333333-3333-3333-3333-333333333333"].waitForExistence(timeout: 10))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.open(URL(string: "https://egoar777.github.io/MonoTask/join/#0123456789abcdef0123456789abcdef")!)
        let link = safari.links.matching(NSPredicate(format: "label BEGINSWITH 'Открыть в MonoTask'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        let shot = XCTAttachment(screenshot: safari.screenshot())
        shot.name = "HTTPSInvitationMobile"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(
            safari.staticTexts["Нажмите, чтобы открыть приглашение в приложении."].waitForExistence(timeout: 15))
        // Let the web font finish laying out before tapping the native link coordinates.
        Thread.sleep(forTimeInterval: 1)
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let confirmation = safari.buttons.matching(NSPredicate(format: "label == 'Open' OR label == 'Открыть'"))
            .firstMatch
        if confirmation.waitForExistence(timeout: 4) { confirmation.tap() }
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "shared-invite-code").firstMatch.waitForExistence(
                timeout: 10))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "shared-invite-code").firstMatch.value as? String,
            "0123456789abcdef0123456789abcdef")
        XCTAssertTrue(app.buttons["shared-confirm-join"].isEnabled)
    }

    func testInvitationOpensJoinSheet() {
        let app = XCUIApplication(bundleIdentifier: "com.monotask")
        app.launchArguments = ["--screenshots", "--shared-preview"]
        app.launch()
        XCTAssertTrue(
            app.buttons["workspace-shared-folder-33333333-3333-3333-3333-333333333333"].waitForExistence(timeout: 10))
        let code = "0123456789abcdef0123456789abcdef"
        app.open(URL(string: "com.monotask.ios://join?code=\(code)")!)
        let field = app.descendants(matching: .any).matching(identifier: "shared-invite-code").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, code)
        XCTAssertTrue(app.buttons["shared-confirm-join"].isEnabled)
        app.buttons["shared-confirm-join"].tap()
        XCTAssertTrue(app.buttons["shared-add-task"].waitForExistence(timeout: 5))
    }

    func testCreateListAndValidateJoinInput() {
        let app = launch()
        app.buttons["shared-join-list"].tap()
        let code = app.descendants(matching: .any).matching(identifier: "shared-invite-code").firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 4))
        code.tap()
        code.typeText("invalid")
        XCTAssertFalse(app.buttons["shared-confirm-join"].isEnabled)
        app.buttons["Отмена"].tap()
        app.buttons["shared-create-list"].tap()
        let name = app.textFields["shared-folder-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        name.tap()
        name.typeText("Новая общая папка")
        app.swipeUp()
        app.buttons["shared-confirm-create"].tap()
        XCTAssertTrue(app.images["shared-invite-qr"].waitForExistence(timeout: 5))
        app.buttons["shared-open-created-folder"].tap()
        XCTAssertTrue(app.buttons["shared-add-task"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["0 / 0 выполнено"].exists)
    }
}
