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

    @MainActor
    func testUpdateMenuShowsAvailableRelease() throws {
        let app = launchUpdateTestApp(mode: "available")
        clickCheckForUpdates(in: app)

        let versionTitle = element("update-version-title", in: app)
        XCTAssertTrue(versionTitle.waitForExistence(timeout: 6))
        XCTAssertEqual(versionTitle.label, "Hosts Manager v9.9.9")
        XCTAssertTrue(app.staticTexts["UI test release notes."].exists)
    }

    @MainActor
    func testSettingsCheckReportsUpToDate() throws {
        let app = launchUpdateTestApp(mode: "upToDate")

        let settingsButton = app.buttons["sidebar-settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.click()

        let checkButton = app.buttons["settings-check-for-updates"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.click()

        XCTAssertTrue(element("update-up-to-date", in: app).waitForExistence(timeout: 6))
    }

    @MainActor
    func testUpdateDownloadCompletesWithoutMountingDMG() throws {
        let app = launchUpdateTestApp(mode: "available")
        clickCheckForUpdates(in: app)

        let downloadButton = app.buttons["update-download-button"]
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 6))
        downloadButton.click()

        XCTAssertTrue(element("update-downloaded", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["update-show-in-finder"].exists)
    }

    @MainActor
    private func launchUpdateTestApp(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestUpdateMode", mode,
            "-UITestDisableHelperGuide"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func clickCheckForUpdates(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["create-profile-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.menuBars.menuBarItems["Hosts Manager"].exists)
        app.typeKey("u", modifierFlags: [.command, .shift])
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
