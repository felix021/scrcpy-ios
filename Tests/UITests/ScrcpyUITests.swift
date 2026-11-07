import XCTest

final class ScrcpyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-reset","-AppleLanguages","(en)","-AppleLocale","en_US"]; app.launch(); return app
    }
    private func replace(_ field: XCUIElement, _ value: String) {
        field.tap(); let previous = field.value as? String ?? ""; field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count:previous.count)+value)
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) { let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment) }
    func testConfigurationAndLanguage() throws {
        let app = launch(); XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout:15))
        replace(app.textFields["host"],"draft-device.example")
        app.buttons["appSettings"].tap(); XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout:5)); XCTAssertTrue(app.staticTexts["appVersion"].exists)
        snapshot(app,"settings-english")
        app.buttons["languagePicker"].tap(); app.buttons["简体中文"].tap(); app.buttons["settingsDone"].tap()
        XCTAssertEqual(app.textFields["host"].value as? String,"draft-device.example"); XCTAssertTrue(app.staticTexts["远程控制"].exists)
        app.buttons["appSettings"].tap(); app.buttons["languagePicker"].tap(); app.buttons["English"].tap(); app.buttons["settingsDone"].tap()
        app.buttons["saveProfile"].tap(); replace(app.textFields["profileName"],"Test device"); app.buttons["saveConfirm"].tap()
        app.buttons["profilePicker"].tap(); XCTAssertTrue(app.buttons["profile.Test device"].waitForExistence(timeout:5)); app.buttons["profile.Test device"].tap()
        app.buttons["deleteProfile"].tap(); XCTAssertTrue(app.buttons["confirmAction"].exists); app.buttons["confirmAction"].tap()
        XCTAssertTrue(app.staticTexts["No saved profiles"].waitForExistence(timeout:5)); snapshot(app,"profiles-empty")
    }
    func testRealAndroidConnection() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let host = environment["SCRCPY_TEST_HOST"] ?? environment["TEST_RUNNER_SCRCPY_TEST_HOST"], !host.isEmpty else { throw XCTSkip("Set SCRCPY_TEST_HOST to an owned Android target") }
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-reset","--autoconnect","-AppleLanguages","(en)"]
        app.launchEnvironment["SCRCPY_TEST_HOST"] = host
        app.launchEnvironment["SCRCPY_TEST_AUDIO"] = environment["TEST_RUNNER_SCRCPY_TEST_AUDIO"] ?? "0"
        app.launchEnvironment["SCRCPY_TEST_CODEC"] = environment["TEST_RUNNER_SCRCPY_TEST_CODEC"] ?? "h264"
        app.launchEnvironment["SCRCPY_TEST_PORT"] = environment["SCRCPY_TEST_PORT"] ?? environment["TEST_RUNNER_SCRCPY_TEST_PORT"] ?? "5555"
        addUIInterruptionMonitor(withDescription:"Local network") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }; return false
        }
        app.launch()
        let state = app.staticTexts["connectionState"]
        XCTAssertTrue(state.waitForExistence(timeout:20))
        let deadline = Date().addingTimeInterval(90)
        while state.value as? String != "ready" && Date() < deadline {
            if app.buttons["connect"].exists && app.otherElements["notice"].exists { XCTFail("Connection failed: " + app.otherElements["notice"].debugDescription); return }
            sleep(1)
        }
        XCTAssertEqual(state.value as? String,"ready")
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"notice").firstMatch.exists)
        snapshot(app,"remote-portrait")
        app.descendants(matching:.any).matching(identifier:"remoteSurface").firstMatch.tap()
        app.buttons["keyboard"].tap(); XCTAssertTrue(app.buttons["key.Ctrl"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["key.Win"].exists || app.otherElements["key.Win"].exists)
        app.buttons["key.Fn"].tap(); app.buttons["key.Menu"].tap()
        snapshot(app,"keyboard-portrait")
        app.buttons["keyboard"].tap()
        app.buttons["runtimeSettings"].tap(); XCTAssertTrue(app.buttons["rotateLeft"].waitForExistence(timeout:5)); app.buttons["rotateRight"].tap(); sleep(2); snapshot(app,"remote-manual-rotation")
        app.buttons["runtimeDone"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(3); snapshot(app,"remote-landscape")
        let surface = app.descendants(matching:.any).matching(identifier:"remoteSurface").firstMatch
        XCTAssertTrue(surface.frame.width > surface.frame.height)
        XCTAssertTrue(app.buttons["runtimeSettings"].isHittable)
        for side in [0.01,0.99] {
            surface.coordinate(withNormalizedOffset:CGVector(dx:side,dy:0.5)).press(forDuration:0.1,thenDragTo:surface.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)))
        }
        let dimensions = (surface.value as? String ?? "").split(separator:"x").compactMap { Double($0) }
        XCTAssertEqual(dimensions.count,2)
        if dimensions.count == 2 {
            let scale = min(surface.frame.width/dimensions[0],surface.frame.height/dimensions[1])
            let margin = (surface.frame.height-dimensions[1]*scale)/2/surface.frame.height
            surface.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:margin+0.01)).press(forDuration:0.1,thenDragTo:surface.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)))
            sleep(1); snapshot(app,"remote-top-gesture")
            surface.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:1-margin-0.01)).press(forDuration:0.1,thenDragTo:surface.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)))
            sleep(1); snapshot(app,"remote-bottom-gesture")
        }
        XCTAssertEqual(state.value as? String,"ready")
        app.buttons["runtimeSettings"].tap()
        if app.launchEnvironment["SCRCPY_TEST_AUDIO"] == "1" { XCTAssertEqual(app.switches["opt.audio"].value as? String,"1") }
        app.buttons["disconnect"].tap(); app.buttons["confirmAction"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout:10)); XCUIDevice.shared.orientation = .portrait
    }
}
