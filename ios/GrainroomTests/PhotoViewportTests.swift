// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import UIKit
@testable import Grainroom

@MainActor final class PhotoViewportTests: XCTestCase {
    private func photo(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image {
            color.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
    }

    private func viewport() -> (PhotoViewport, UIImage, UIImage) {
        let developed = photo(.red), original = photo(.blue)
        let view = PhotoViewport(zoomEnabled: true)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.setPhotos(image: developed, original: original)
        view.layoutIfNeeded()
        return (view, developed, original)
    }

    func testNativeViewportFitsWholePhotoAndRecentersAfterRotation() {
        let (view, _, _) = viewport()
        let frame = view.imageView.convert(view.imageView.bounds, to: view)
        XCTAssertEqual(frame.width, 390, accuracy: 0.01)
        XCTAssertEqual(frame.height, 292.5, accuracy: 0.01)
        // UIScrollView rounds content offsets to display pixels.
        let pixel = 1 / max(view.traitCollection.displayScale, 1)
        XCTAssertEqual(frame.midY, 422, accuracy: pixel)
        view.scrollView.setZoomScale(3, animated: false)
        XCTAssertEqual(view.imageView.frame.width, 1170, accuracy: 0.01)
        view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        view.setNeedsLayout(); view.layoutIfNeeded()
        let rotated = view.imageView.convert(view.imageView.bounds, to: view)
        XCTAssertEqual(view.scrollView.zoomScale, 1)
        XCTAssertEqual(rotated.size, CGSize(width: 520, height: 390))
        XCTAssertEqual(rotated.midX, 422, accuracy: pixel)
    }

    func testPressReleaseAndCancellationKeepTheSameZoomedRegion() {
        let (view, developed, original) = viewport()
        view.scrollView.setZoomScale(3, animated: false)
        view.scrollView.contentOffset = CGPoint(x: 120, y: 16)
        let frame = view.imageView.frame, offset = view.scrollView.contentOffset
        for finish in [UIGestureRecognizer.State.ended, .cancelled, .failed] {
            view.compare(.began)
            XCTAssertTrue(view.imageView.image === original)
            XCTAssertTrue(view.isComparing)
            XCTAssertEqual(view.accessibilityLabel, "原图预览")
            XCTAssertEqual(view.imageView.frame, frame)
            XCTAssertEqual(view.scrollView.contentOffset, offset)
            view.compare(finish)
            XCTAssertTrue(view.imageView.image === developed)
            XCTAssertFalse(view.isComparing)
            XCTAssertEqual(view.scrollView.zoomScale, 3)
            XCTAssertEqual(view.scrollView.contentOffset, offset)
        }
    }

    func testPinchAndInterruptionRestoreDevelopedPhoto() {
        let (view, developed, _) = viewport()
        view.compare(.began)
        view.scrollViewWillBeginZooming(view.scrollView, with: view.imageView)
        XCTAssertTrue(view.imageView.image === developed)
        XCTAssertFalse(view.hold.isEnabled)
        view.scrollViewDidEndZooming(view.scrollView, with: view.imageView, atScale: 2)
        XCTAssertTrue(view.hold.isEnabled)
        view.compare(.began)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertTrue(view.imageView.image === developed)
        XCTAssertFalse(view.isComparing)
    }

    func testSwiftUIUpdatesDoNotResetZoomAndInlineDoesNotStealScrolling() {
        let (view, developed, original) = viewport()
        view.scrollView.setZoomScale(2, animated: false)
        view.setPhotos(image: developed, original: original)
        view.layoutIfNeeded()
        XCTAssertEqual(view.scrollView.zoomScale, 2)
        let inline = PhotoViewport(zoomEnabled: false)
        XCTAssertFalse(inline.scrollView.isScrollEnabled)
        XCTAssertEqual(inline.scrollView.maximumZoomScale, 1)
        inline.setPhotos(image: developed, original: nil)
        inline.compare(.began)
        XCTAssertFalse(inline.isComparing)
        XCTAssertTrue(inline.imageView.image === developed)
    }
}
