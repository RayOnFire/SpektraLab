// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class PhotoImportUITests: XCTestCase {
    @MainActor func testToolbarPhotoImportPresentsPickerAndCanReopenAfterCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        guard app.staticTexts["色彩测试图"].waitForExistence(timeout: 30) else {
            XCTFail("Run the photo picker test on a dedicated Simulator with the built-in demo image.")
            return
        }
        for _ in 0..<2 {
            app.buttons["导入照片"].tap()
            let importPhoto = app.buttons["从照片导入"]
            XCTAssertTrue(importPhoto.waitForExistence(timeout: 5))
            importPhoto.tap()
            let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
            guard cancel.waitForExistence(timeout: 10) else {
                XCTFail("Photo library picker was not presented: \(app.debugDescription)")
                return
            }
            cancel.tap()
            XCTAssertTrue(app.buttons["导入照片"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["色彩测试图"].exists, "Cancelling must preserve the current edit")
        }
    }
}
