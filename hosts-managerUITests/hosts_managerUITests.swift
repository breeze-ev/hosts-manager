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
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
