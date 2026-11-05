// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@main struct GrainroomApp: App {
    @State private var model = EditorModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            EditorView(model: model)
                .tint(Color(red: 0.92, green: 0.66, blue: 0.38))
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in
                    if value == .background { model.suspend() }
                    if value == .active, model.photo == nil { model.schedule() }
                }
                .onOpenURL { url in Task { await model.importPhoto(url) } }
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--demo"), model.sourceURL == nil { await model.demo() }
                }
        }
    }
}
