// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

struct PhotoPreview: UIViewRepresentable {
    let image: UIImage
    let original: UIImage?
    let zoomEnabled: Bool
    var onTap: () -> Void = {}

    func makeUIView(context: Context) -> PhotoViewport { PhotoViewport(zoomEnabled: zoomEnabled) }

    func updateUIView(_ view: PhotoViewport, context: Context) {
        view.onTap = onTap
        view.setPhotos(image: image, original: original)
    }

    static func dismantleUIView(_ view: PhotoViewport, coordinator: ()) { view.compare(.cancelled) }
}

/// One image surface for editor and full screen. Swapping the already rendered
/// images preserves the scroll view's transform and does not call the engine.
@MainActor final class PhotoViewport: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let imageView = UIImageView()
    let hold = UILongPressGestureRecognizer()
    private let originalBadge = UILabel()
    private let zoomEnabled: Bool
    private var image: UIImage?
    private var original: UIImage?
    private var fittedBounds = CGSize.zero
    private var needsFit = true
    private(set) var isComparing = false
    var onTap: (() -> Void)?

    init(zoomEnabled: Bool) {
        self.zoomEnabled = zoomEnabled
        super.init(frame: .zero)
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = zoomEnabled ? 8 : 1
        scrollView.isScrollEnabled = zoomEnabled
        scrollView.pinchGestureRecognizer?.isEnabled = zoomEnabled
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = zoomEnabled
        addSubview(scrollView)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 12
        hold.delegate = self
        hold.addTarget(self, action: #selector(held(_:)))
        addGestureRecognizer(hold)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: hold)
        addGestureRecognizer(tap)
        if zoomEnabled {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            tap.require(toFail: doubleTap)
            addGestureRecognizer(doubleTap)
        }

        originalBadge.text = "原图"
        originalBadge.textColor = .white
        originalBadge.font = .preferredFont(forTextStyle: .caption1)
        originalBadge.textAlignment = .center
        originalBadge.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        originalBadge.layer.cornerRadius = 8
        originalBadge.clipsToBounds = true
        originalBadge.isHidden = true
        originalBadge.isAccessibilityElement = false
        originalBadge.isUserInteractionEnabled = false
        addSubview(originalBadge)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityIdentifier = zoomEnabled ? "photo.fullscreenCanvas" : "photo.editorCanvas"
        accessibilityHint = zoomEnabled ? "双指缩放，放大后拖动。长按查看原图，松开恢复。轻点显示按钮。" : "轻点全屏查看，长按查看原图，松开恢复。"
        updateAccessibility()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    func setPhotos(image: UIImage, original: UIImage?) {
        guard self.image !== image || self.original !== original else { return }
        let geometryChanged = self.image?.size != image.size
        self.image = image; self.original = original
        compare(.cancelled)
        if geometryChanged { needsFit = true; setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        originalBadge.frame = CGRect(x: bounds.width - safeAreaInsets.right - 66,
                                     y: safeAreaInsets.top + 12, width: 52, height: 28)
        guard let image, bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }
        if needsFit || fittedBounds != bounds.size {
            compare(.cancelled)
            scrollView.setZoomScale(1, animated: false)
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            fittedBounds = bounds.size; needsFit = false
            centerImage()
            scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        } else { centerImage() }
        updateAccessibility()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(); updateAccessibility() }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        compare(.cancelled)
        hold.isEnabled = false
    }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        hold.isEnabled = true
    }

    private func centerImage() {
        let x = max(0, (scrollView.bounds.width - imageView.frame.width) / 2)
        let y = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func compare(_ state: UIGestureRecognizer.State) {
        isComparing = (state == .began || state == .changed) && original != nil
        imageView.image = isComparing ? original : image
        originalBadge.isHidden = !isComparing
        updateAccessibility()
    }

    private func updateAccessibility() {
        accessibilityLabel = isComparing ? "原图预览" : "胶片显影预览"
        accessibilityValue = "\(Int((scrollView.zoomScale * 100).rounded()))%"
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) { compare(gesture.state) }
    @objc private func tapped() { onTap?() }
    @objc private func interrupted() { compare(.cancelled); hold.isEnabled = true }
    override func accessibilityActivate() -> Bool { onTap?(); return true }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { compare(.cancelled) }
        super.willMove(toWindow: newWindow)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        compare(.cancelled)
        if scrollView.zoomScale > 1.01 { scrollView.setZoomScale(1, animated: true) }
        else {
            let center = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === hold {
            return original != nil && !scrollView.isZooming && !scrollView.isDragging &&
                (scrollView.pinchGestureRecognizer?.numberOfTouches ?? 0) < 2
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === hold && otherGestureRecognizer === scrollView.pinchGestureRecognizer) ||
            (otherGestureRecognizer === hold && gestureRecognizer === scrollView.pinchGestureRecognizer)
    }
}
