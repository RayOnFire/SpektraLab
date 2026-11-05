// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class PhotoViewerUITests: XCTestCase {
    @MainActor func testFullscreenPinchHoldAndReturnToEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let open = app.buttons["全屏查看照片"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        XCTAssertTrue(expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: open).waitForFulfillment(timeout: 30))
        open.tap()
        let image = app.images["photo.fullscreenCanvas"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertEqual(image.label, "胶片显影预览")
        let importButton = app.buttons["导入照片"]
        if importButton.exists { XCTAssertFalse(importButton.isHittable) }
        let hiddenControls = NSPredicate(format: "exists == false")
        XCTAssertTrue(expectation(for: hiddenControls, evaluatedWith: app.buttons["退出全屏"]).waitForFulfillment(timeout: 5))
        let fullscreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fullscreen.name = "Grainroom-fullscreen"; fullscreen.lifetime = .keepAlways
        add(fullscreen)
        image.pinch(withScale: 2, velocity: 1)
        let enlarged = NSPredicate(format: "value != %@", "100%")
        XCTAssertTrue(expectation(for: enlarged, evaluatedWith: image).waitForFulfillment(timeout: 5))
        image.press(forDuration: 0.6)
        XCTAssertEqual(image.label, "胶片显影预览", "Release must restore the applied result")
        image.doubleTap()
        let fitted = NSPredicate(format: "value == %@", "100%")
        XCTAssertTrue(expectation(for: fitted, evaluatedWith: image).waitForFulfillment(timeout: 5))
        if !app.buttons["退出全屏"].isHittable { image.tap() }
        let close = app.buttons["退出全屏"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let editor = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editor.name = "Grainroom-editor"; editor.lifetime = .keepAlways
        add(editor)
    }
}

private extension XCTestExpectation {
    func waitForFulfillment(timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [self], timeout: timeout) == .completed
    }
}
