// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct FullScreenPhotoView: View {
    let image: UIImage
    let original: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PhotoPreview(image: image, original: original, zoomEnabled: true) {
                withAnimation(.easeInOut(duration: 0.15)) { controlsVisible.toggle() }
            }.ignoresSafeArea()
            if controlsVisible {
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }.accessibilityLabel("退出全屏")
                        Spacer()
                    }
                    Spacer()
                    Text("双指缩放 · 放大后拖动 · 长按查看原图\n轻点画面显示或隐藏按钮")
                        .font(.caption).multilineTextAlignment(.center)
                        .padding(12).background(.ultraThinMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(.white).transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }
}
