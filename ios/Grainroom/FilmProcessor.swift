// SPDX-License-Identifier: GPL-3.0-or-later
// Uses SpektraLab's existing C ABI and shared Core Image decoder. No changes
// to the material model, resource arrays or Metal compute kernels.
import CoreImage
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct DevelopedPhoto: @unchecked Sendable {
    let image: CGImage
    let original: CGImage
    let isRAW: Bool
    let asShotTemperature: Double?
    let width: Int
    let height: Int
}

enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case jpeg = "JPEG", png = "PNG"
    var id: String { rawValue }
    var suffix: String { self == .jpeg ? "jpg" : "png" }
    var type: UTType { self == .jpeg ? .jpeg : .png }
}

actor FilmProcessor {
    private final class Handles: @unchecked Sendable {
        var engine: OpaquePointer?
        var session: OpaquePointer?
        func clear() {
            if let session { spk_session_release(session); self.session = nil }
            if let engine { spk_engine_destroy(engine); self.engine = nil }
        }
        deinit { clear() }
    }
    private let handles = Handles()
    private let device: MTLDevice
    private var key: DecodeKey?
    private var original: CGImage?
    private var raw = false
    private var asShotTemperature: Double?
    private var lastFilm = ""
    private var lastPaper = ""
    private var appliedParameters: [String: Any] = [:]
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private struct DecodeKey: Equatable {
        let url: URL
        let edge: Int
        let decode: DecodeSettings
        let crop: CropRatio
        let turns: Int
        let mirror: Bool
    }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw PhotoFailure.message("设备不支持 Metal。") }
        self.device = device
    }

    func clear() {
        handles.clear(); key = nil; original = nil; lastFilm = ""; lastPaper = ""
        appliedParameters = [:]
        ImageDecoder.context.clearCaches()
    }

    static func boundedEdge(width: Int, height: Int, requested: Int) -> Int {
        guard width > 0, height > 0 else { return min(requested, 2560) }
        let pixels = Double(width) * Double(height)
        let scale = min(1, min(Double(requested) / Double(max(width, height)), sqrt(12_000_000 / pixels)))
        return max(1, Int((Double(max(width, height)) * scale).rounded(.down)))
    }

    func render(url: URL, settings: PhotoSettings, film: FilmStock?, requestedEdge: Int = 1600) throws -> DevelopedPhoto {
        try Task.checkCancellation()
        let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let props = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let edge = Self.boundedEdge(width: width, height: height, requested: requestedEdge)
        let wantedKey = DecodeKey(url: url, edge: edge, decode: settings.decode, crop: settings.crop,
                                  turns: settings.quarterTurns, mirror: settings.mirror)
        let needsOpen = key != wantedKey || handles.session == nil
        if needsOpen {
            // Release both the previous decode and its GPU pool before a larger
            // export. The desktop app's native-resolution idle render is absent.
            clear()
        }
        let parameters: [String: Any] = [
            "film_stock": settings.film, "print_stock": settings.paper,
            "product_defaults": true, "exposure_compensation_ev": settings.exposure,
            "print_exposure": pow(2, -settings.printBrightness),
            "grain_active": settings.grain > 0, "grain_amount": settings.grain,
            "grain_sublayers_active": !(film?.isMonochrome ?? false),
            "halation_active": settings.halation > 0, "halation_amount": settings.halation,
            "glare_active": false, "scan_film": film?.isPositive ?? false,
            "input_color_space": "ProPhoto RGB", "input_cctf_decoding": false,
            "output_color_space": "sRGB", "output_cctf_encoding": true,
            "preview_long_edge": 1600,
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]), as: UTF8.self)
        if needsOpen {
            let decoded = try ImageDecoder.decode(url, settings: settings.decode, maxLongEdge: edge,
                                                  checkpoint: { try Task.checkCancellation() })
            let framed = Self.frame(decoded, settings: settings)
            let count = Int(framed.pixelSize.width) * Int(framed.pixelSize.height)
            guard count > 0, count <= 12_100_000 else { throw PhotoFailure.message("图像尺寸超出首版的 1200 万像素限制。") }
            // Conservative admission heuristic, not a measured device memory
            // guarantee. Real-device profiling is still required (README).
            let available = os_proc_available_memory()
            if available > 0, Double(count) * 180 + 64_000_000 > Double(available) * 0.8 {
                throw PhotoFailure.message("当前可用内存不足，请选择较小的导出尺寸。")
            }
            let resources = Bundle.main.bundleURL.appendingPathComponent("GrainroomData/engine").path
            guard let engine = spk_engine_create(resources, Unmanaged.passUnretained(device as AnyObject).toOpaque()) else {
                throw PhotoFailure.message(String(cString: spk_last_error(nil)))
            }
            handles.engine = engine
            try autoreleasepool {
                let frame = try ImageDecoder.engineFrame(from: framed, device: device)
                var input = spk_device_image(buffer: Unmanaged.passUnretained(frame.buffer as AnyObject).toOpaque(),
                                             width: UInt32(frame.width), height: UInt32(frame.height), channels: 4)
                var reply: UnsafeMutablePointer<CChar>?
                handles.session = spk_open_device(engine, &input, json, &reply)
                if let reply { spk_string_free(reply) }
                guard handles.session != nil else { throw failure() }
            }
            original = ImageDecoder.context.createCGImage(framed.display, from: framed.display.extent,
                                                          format: .RGBA8, colorSpace: space)
            raw = framed.isRAW
            asShotTemperature = framed.asShotTemperature
            key = wantedKey
        } else {
            // product_defaults is an open option, not a set_params field.
            // Sending unchanged stock keys also forces a pipeline rebuild.
            let delta = parameters.filter { name, value in
                name != "product_defaults" && !((value as? NSObject)?.isEqual(appliedParameters[name]) ?? false)
            }
            if !delta.isEmpty {
                let deltaJSON = String(decoding: try JSONSerialization.data(withJSONObject: delta, options: [.sortedKeys]), as: UTF8.self)
                var reply: UnsafeMutablePointer<CChar>?
                let status = spk_set_params(handles.session, deltaJSON, &reply)
                if let reply { spk_string_free(reply) }
                guard status == SPK_OK else { throw failure() }
            }
        }
        appliedParameters = parameters
        try Task.checkCancellation()
        if needsOpen || lastFilm != settings.film || lastPaper != settings.paper {
            if !(film?.isPositive ?? false) {
                var reply: UnsafeMutablePointer<CChar>?
                let status = spk_solve(handles.session, "filter_pack", &reply)
                if let reply { spk_string_free(reply) }
                guard status == SPK_OK else { throw failure() }
            }
            lastFilm = settings.film; lastPaper = settings.paper
        }
        var result = spk_result()
        guard spk_reprint(handles.session, "full", &result) == SPK_OK else { throw failure() }
        defer { spk_result_free(&result) }
        try Task.checkCancellation()
        guard let pixels = result.rgba16, let original else { throw PhotoFailure.message("显影没有返回图像。") }
        let rowBytes = Int(result.row_stride_px) * 8
        let data = Data(bytes: pixels, count: rowBytes * Int(result.height))
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: Int(result.width), height: Int(result.height), bitsPerComponent: 16,
                                  bitsPerPixel: 64, bytesPerRow: rowBytes, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw PhotoFailure.message("无法读取显影图像。") }
        return DevelopedPhoto(image: image, original: original, isRAW: raw, asShotTemperature: asShotTemperature,
                              width: image.width, height: image.height)
    }

    func export(url: URL, settings: PhotoSettings, film: FilmStock?, edge: Int, kind: ExportKind) throws -> URL {
        defer { clear() }
        let result = try render(url: url, settings: settings, film: film, requestedEdge: edge)
        try Task.checkCancellation()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Grainroom-\(UUID().uuidString).\(kind.suffix)")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, kind.type.identifier as CFString, 1, nil) else {
            throw PhotoFailure.message("无法创建导出文件。")
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if kind == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.94 }
        var exif = ImageDecoder.sourceEXIF(from: url) ?? [:]
        exif[kCGImagePropertyExifPixelXDimension] = result.width
        exif[kCGImagePropertyExifPixelYDimension] = result.height
        properties[kCGImagePropertyExifDictionary] = exif
        CGImageDestinationAddImage(destination, result.image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoFailure.message("导出未能完成。") }
        return output
    }

    private func failure() -> PhotoFailure { .message(String(cString: spk_last_error(handles.engine))) }

    static func frame(_ decoded: DecodedImage, settings: PhotoSettings) -> DecodedImage {
        func transform(_ source: CIImage) -> CIImage {
            var image = source
            let orientations: [Int32] = [1, 6, 3, 8]
            image = image.oriented(forExifOrientation: orientations[settings.quarterTurns.clamped(to: 0...3)])
            if settings.mirror { image = image.oriented(forExifOrientation: 2) }
            var bounds = image.extent.integral
            if let ratio = settings.crop.ratio {
                if bounds.width / bounds.height > ratio {
                    let width = floor(bounds.height * ratio)
                    bounds = CGRect(x: bounds.midX - width / 2, y: bounds.minY, width: width, height: bounds.height)
                } else {
                    let height = floor(bounds.width / ratio)
                    bounds = CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
                }
            }
            bounds = bounds.integral.intersection(image.extent.integral)
            return image.cropped(to: bounds).transformed(by: .init(translationX: -bounds.minX, y: -bounds.minY))
        }
        let linear = transform(decoded.linear), display = transform(decoded.display)
        return DecodedImage(linear: linear, display: display, pixelSize: linear.extent.size,
                            isRAW: decoded.isRAW, lensCorrectionSupported: decoded.lensCorrectionSupported,
                            sourceURL: decoded.sourceURL, sourceEXIF: decoded.sourceEXIF,
                            asShotTemperature: decoded.asShotTemperature, asShotTint: decoded.asShotTint)
    }
}
