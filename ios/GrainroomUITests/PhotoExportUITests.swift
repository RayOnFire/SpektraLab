// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class PhotoExportUITests: XCTestCase {
    @MainActor func testJPEGExportActuallySavesToPhotosWithoutCrashing() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        // Never write a user's restored edit into their library during tests.
        guard app.staticTexts["色彩测试图"].waitForExistence(timeout: 30) else {
            XCTFail("Run the Photos write test on a dedicated Simulator with the built-in demo image.")
            return
        }
        let export = app.buttons["导出照片"]
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: export)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        export.tap()
        let generate = app.buttons["生成导出文件"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        let save = app.buttons["保存到照片"]
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        save.tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let allowedTitles = ["Allow", "Allow Adding Photos", "Add Photos Only", "允许", "允许添加照片", "仅添加照片"]
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", allowedTitles)).firstMatch
            XCTAssertTrue(allow.exists, alert.debugDescription)
            allow.tap()
        }
        // This is set only after Photos' real transaction completes. A fresh
        // launch owns its in-memory notice; no persisted success can satisfy it.
        XCTAssertTrue(app.staticTexts["已保存到照片"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["保存到照片"].exists)
    }
}
