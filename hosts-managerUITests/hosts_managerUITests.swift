//
//  hosts_managerUITests.swift
//  hosts-managerUITests
//
//  Created by Breeze on 2026-08-19.
//

import XCTest

final class hosts_managerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSystemProfileCannotOpenApplyFlowWithKeyboardShortcut() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let systemProfile = app.buttons["profile-row-系统"]
        XCTAssertTrue(systemProfile.waitForExistence(timeout: 8))
        systemProfile.click()

        app.typeKey("s", modifierFlags: .command)
        XCTAssertFalse(app.buttons["confirm-apply-button"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testEditorOpensWithoutHanging() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let defaultProfile = app.buttons["profile-row-默认"]
        XCTAssertTrue(defaultProfile.waitForExistence(timeout: 8))
        defaultProfile.click()

        let editMode = app.radioButtons["pencil"].firstMatch
        XCTAssertTrue(editMode.waitForExistence(timeout: 4))
        editMode.click()

        let validate = app.buttons
            .matching(NSPredicate(format: "label == %@ OR label == %@", "校验", "Validate"))
            .firstMatch
        if !validate.waitForExistence(timeout: 12) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "EditorFailure"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Editor toolbar did not appear after switching to edit mode.")
        }
    }

    @MainActor
    func testToolbarTitlesStayAlignedAndStatusBadgeFollowsTitle() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let defaultProfile = app.buttons["profile-row-默认"]
        XCTAssertTrue(defaultProfile.waitForExistence(timeout: 8))
        defaultProfile.click()

        let title = app.staticTexts["detail-toolbar-title"]
        let badge = app.staticTexts["profile-status-badge"]
        let search = app.textFields["toolbar-search-field"]

        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertTrue(badge.waitForExistence(timeout: 4))
        XCTAssertTrue(search.waitForExistence(timeout: 4))

        let window = app.windows.firstMatch
        XCTAssertLessThan(title.frame.midX, window.frame.midX)
        XCTAssertLessThan(title.frame.maxX, badge.frame.minX)
        XCTAssertLessThan(badge.frame.minX - title.frame.maxX, 24)
        XCTAssertGreaterThan(search.frame.midX, window.frame.midX)

        let initialTitleMinX = title.frame.minX
        let initialTitleWidth = title.frame.width
        let longerProfile = app.buttons["profile-row-ze.local"]
        XCTAssertTrue(longerProfile.waitForExistence(timeout: 4))
        longerProfile.click()

        let longerTitle = NSPredicate(format: "value == %@", "ze.local")
        expectation(for: longerTitle, evaluatedWith: title)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(title.frame.minX, initialTitleMinX, accuracy: 1)
        XCTAssertGreaterThan(title.frame.width, initialTitleWidth)
        XCTAssertLessThan(title.frame.maxX, badge.frame.minX)
        XCTAssertLessThan(badge.frame.minX - title.frame.maxX, 24)

        let backup = app.buttons["clock.arrow.circlepath"]
        XCTAssertTrue(backup.waitForExistence(timeout: 4))
        backup.click()
        expectation(for: NSPredicate(format: "value == %@", "备份"), evaluatedWith: title)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(title.frame.minX, initialTitleMinX, accuracy: 1)

        let settings = app.buttons["sidebar-settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 4))
        settings.click()
        expectation(for: NSPredicate(format: "value == %@", "设置"), evaluatedWith: title)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(title.frame.minX, initialTitleMinX, accuracy: 1)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ToolbarCustomTitle"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
