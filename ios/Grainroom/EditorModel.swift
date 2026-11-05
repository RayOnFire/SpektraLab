// SPDX-License-Identifier: GPL-3.0-or-later
import CoreTransferable
import Foundation
import ImageIO
import Observation
import Photos
import UIKit
import UniformTypeIdentifiers

struct PickedPhoto: Transferable, Sendable {
    let url: URL
    let title: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedPhoto(url: target, title: received.file.deletingPathExtension().lastPathComponent)
        }
    }
}

struct SavedEdit: Codable {
    let filename: String
    let title: String
    let settings: PhotoSettings
}

@MainActor @Observable
final class EditorModel {
    var settings = PhotoSettings()
    var library = FilmLibrary(stocks: [])
    var photo: UIImage?
    var original: UIImage?
    var sourceURL: URL?
    var title = ""
    var dimensions = ""
    var isRAW = false
    var isRendering = false
    var isExporting = false
    var error: String?
    var exportURL: URL?
    var notice: String?
    @ObservationIgnored private var processor: FilmProcessor?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Grainroom")
    }

    init() {
        do {
            library = try FilmLibrary.load()
            processor = try FilmProcessor()
            let savedURL = directory.appendingPathComponent("edit.json")
            if let data = try? Data(contentsOf: savedURL), let saved = try? JSONDecoder().decode(SavedEdit.self, from: data) {
                let url = directory.appendingPathComponent(saved.filename)
                if FileManager.default.fileExists(atPath: url.path) {
                    sourceURL = url; title = saved.title; settings = saved.settings
                    schedule()
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func importPhoto(_ url: URL, title: String? = nil, removeTemporary: Bool = false) async {
        guard !isExporting else { return }
        task?.cancel(); generation += 1
        let gen = generation
        isRendering = true; error = nil; notice = nil
        do {
            let folder = directory
            let destination = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                try FileManager.default.copyItem(at: url, to: target)
                return target
            }.value
            if removeTemporary { try? FileManager.default.removeItem(at: url) }
            guard gen == generation else { try? FileManager.default.removeItem(at: destination); return }
            let old = sourceURL
            sourceURL = destination; self.title = title ?? url.deletingPathExtension().lastPathComponent
            settings = PhotoSettings()
            photo = nil; original = nil; exportURL = nil
            save()
            if let old, old.deletingLastPathComponent() == folder { try? FileManager.default.removeItem(at: old) }
            schedule()
        } catch {
            if gen == generation { self.error = error.localizedDescription; isRendering = false }
        }
    }

    func chooseFilm(_ stock: FilmStock) {
        settings.film = stock.id
        if let paper = stock.targetPrint { settings.paper = paper }
        else if !library.papers(for: stock).contains(where: { $0.id == settings.paper }),
                let first = library.papers(for: stock).first { settings.paper = first.id }
        schedule()
    }

    func schedule() {
        guard let url = sourceURL, let processor, !isExporting else { return }
        task?.cancel(); generation += 1
        let gen = generation, current = settings, film = library.stock(settings.film)
        exportURL = nil; isRendering = true
        save()
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
                let result = try await processor.render(url: url, settings: current, film: film)
                try Task.checkCancellation()
                guard let self, gen == generation else { return }
                photo = UIImage(cgImage: result.image)
                original = UIImage(cgImage: result.original)
                dimensions = "\(result.width) × \(result.height)"
                isRAW = result.isRAW; isRendering = false
            } catch is CancellationError { }
            catch {
                guard let self, gen == generation else { return }
                self.error = error.localizedDescription; isRendering = false
            }
        }
    }

    func export(edge: Int, kind: ExportKind) async {
        guard let url = sourceURL, let processor, !isExporting else { return }
        task?.cancel(); generation += 1
        isExporting = true; isRendering = false; exportURL = nil; error = nil
        defer { isExporting = false }
        do { exportURL = try await processor.export(url: url, settings: settings, film: library.stock(settings.film), edge: edge, kind: kind) }
        catch { self.error = error.localizedDescription }
    }

    func saveToPhotos() async {
        guard let url = exportURL else { return }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            error = "照片保存权限未开启。你也可以使用分享菜单保存到文件。"; return
        }
        do {
            // Photos invokes this block on its own serial queue. @Sendable
            // prevents inheriting this model's MainActor isolation in Swift 6.
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            }
            notice = "已保存到照片"
        } catch { self.error = error.localizedDescription }
    }

    func suspend() {
        task?.cancel(); generation += 1; isRendering = false
        save()
        guard !isExporting, let processor else { return }
        Task { await processor.clear() }
    }

    func reset() { settings = PhotoSettings(); schedule() }

    func demo() async {
        do {
            let url = try DemoImage.make()
            await importPhoto(url, title: "色彩测试图", removeTemporary: true)
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let sourceURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let saved = SavedEdit(filename: sourceURL.lastPathComponent, title: title, settings: settings)
            try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("edit.json"), options: .atomic)
        } catch { self.error = "编辑记录未能保存：\(error.localizedDescription)" }
    }
}

enum DemoImage {
    static func make(width: Int = 1200, height: Int = 900) throws -> URL {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let colors: [(Double, Double, Double)] = [(0.75,0.25,0.19),(0.92,0.65,0.19),(0.28,0.56,0.37),(0.12,0.46,0.67),(0.50,0.32,0.62),(0.78,0.52,0.40)]
        for y in 0..<height { for x in 0..<width {
            let offset = (y * width + x) * 4
            let value: (Double, Double, Double)
            if y < height * 2 / 3 {
                let color = colors[min(5, x * 6 / width)]
                let gain = 0.25 + 0.75 * (1 - Double(y) / Double(height))
                value = (color.0 * gain, color.1 * gain, color.2 * gain)
            } else {
                let gray = Double(x) / Double(width - 1)
                value = (gray, gray, gray)
            }
            pixels[offset] = UInt8((value.0 * 255).clamped(to: 0...255))
            pixels[offset+1] = UInt8((value.1 * 255).clamped(to: 0...255))
            pixels[offset+2] = UInt8((value.2 * 255).clamped(to: 0...255))
        } }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw PhotoFailure.message("无法创建测试图。") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("色彩测试图-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PhotoFailure.message("无法保存测试图。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PhotoFailure.message("无法保存测试图。") }
        return url
    }
}
