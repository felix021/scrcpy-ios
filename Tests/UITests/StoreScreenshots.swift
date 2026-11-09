import XCTest

// Opt-in capture on an owned simulator and an explicitly authorized Android.
// No fixture code or connection configuration is included in release builds.
final class StoreScreenshots: XCTestCase {
    func testCaptureProductScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let host = environment["STORE_CAPTURE_HOST"], !host.isEmpty else {
            throw XCTSkip("Set STORE_CAPTURE_HOST for an owned App Store capture target")
        }
        continueAfterFailure = false
        let chinese = environment["STORE_CAPTURE_LANGUAGE"] == "zh"
        let language = chinese ? "zh-Hans" : "en"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-reset", "-AppleLanguages", "(\(language))"]
        app.launchEnvironment["SCRCPY_TEST_HOST"] = "android.local"
        app.launchEnvironment["SCRCPY_TEST_PORT"] = "5555"
        app.launch()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 20))
        app.buttons["appSettings"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons[chinese ? "简体中文" : "English"].tap()
        app.buttons["settingsDone"].tap()
        capture("01-connection")
        app.terminate()

        app.launchEnvironment["SCRCPY_TEST_HOST"] = host
        app.launchEnvironment["SCRCPY_TEST_PORT"] = environment["STORE_CAPTURE_PORT"] ?? "15555"
        app.launchEnvironment["SCRCPY_TEST_AUDIO"] = "0"
        addUIInterruptionMonitor(withDescription: "Local network") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 20))
        app.buttons["connect"].tap()
        let state = app.staticTexts["connectionState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        let deadline = Date().addingTimeInterval(90)
        while state.value as? String != "ready" && Date() < deadline { sleep(1) }
        XCTAssertEqual(state.value as? String, "ready")
        capture("02-remote-control")
        app.buttons["keyboard"].tap()
        XCTAssertTrue(app.buttons["key.Ctrl"].waitForExistence(timeout: 5))
        capture("03-keyboard")
        app.buttons["keyboard"].tap()
        app.buttons["runtimeSettings"].tap()
        XCTAssertTrue(app.buttons["rotateRight"].waitForExistence(timeout: 5))
        capture("04-runtime-settings")
        app.buttons["runtimeDone"].tap()
        app.buttons["runtimeSettings"].tap()
        app.buttons["disconnect"].tap()
        app.buttons["confirmAction"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
