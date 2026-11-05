// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import CoreImage
import ImageIO
@testable import Grainroom

final class FilmProcessorTests: XCTestCase {
    func testExportBudgetBoundsSquareAndCameraSizes() {
        XCTAssertEqual(FilmProcessor.boundedEdge(width: 8000, height: 6000, requested: 1600), 1600)
        XCTAssertEqual(FilmProcessor.boundedEdge(width: 640, height: 480, requested: 4096), 640)
        let edge = FilmProcessor.boundedEdge(width: 8000, height: 8000, requested: 4096)
        XCTAssertLessThanOrEqual(edge * edge, 12_000_000)
    }

    func testDecodeIsBoundedBeforeEngineFrameAndCropMatchesOriginal() throws {
        let url = try DemoImage.make(width: 800, height: 600)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try ImageDecoder.decode(url, settings: DecodeSettings(), maxLongEdge: 200)
        XCTAssertEqual(decoded.pixelSize, CGSize(width: 200, height: 150))
        var settings = PhotoSettings(); settings.crop = .square; settings.quarterTurns = 1
        let framed = FilmProcessor.frame(decoded, settings: settings)
        XCTAssertEqual(framed.pixelSize, CGSize(width: 150, height: 150))
        XCTAssertEqual(framed.linear.extent, framed.display.extent)
    }

    func testHEICImportAppliesOrientationBeforeBoundedDecode() async throws {
        let png = try DemoImage.make(width: 256, height: 192)
        let heic = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
        defer { try? FileManager.default.removeItem(at: png); try? FileManager.default.removeItem(at: heic) }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(heic as CFURL, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoded = try ImageDecoder.decode(heic, settings: DecodeSettings(), maxLongEdge: 128)
        XCTAssertEqual(decoded.pixelSize, CGSize(width: 96, height: 128))
        let engine = try FilmProcessor(), library = try FilmLibrary.load()
        var settings = PhotoSettings(); settings.grain = 0
        let result = try await engine.render(url: heic, settings: settings, film: library.stock(settings.film), requestedEdge: 128)
        XCTAssertEqual(result.width, 96); XCTAssertEqual(result.height, 128)
        await engine.clear()
    }

    func testActualEngineEditsAndJPEGPNGReadback() async throws {
        let url = try DemoImage.make(width: 256, height: 192)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = try FilmProcessor()
        let library = try FilmLibrary.load()
        var settings = PhotoSettings(); settings.grain = 0
        let film = library.stock(settings.film)
        let first = try await engine.render(url: url, settings: settings, film: film)
        XCTAssertEqual(first.width, 256); XCTAssertEqual(first.height, 192)
        // The source has a red patch at the top and a neutral ramp at the
        // bottom. This catches a flipped C ABI/CGImage row convention.
        let top = rgb(first.image, x: 20, y: 16), bottom = rgb(first.image, x: 20, y: 176)
        XCTAssertGreaterThan(top[0], max(top[1], top[2]) + 1000)
        XCTAssertLessThan(bottom.max()! - bottom.min()!, 1000)
        settings.exposure = 1
        let second = try await engine.render(url: url, settings: settings, film: film)
        XCTAssertNotEqual(first.image.dataProvider?.data as Data?, second.image.dataProvider?.data as Data?)
        settings.crop = .square; settings.quarterTurns = 1
        for kind in ExportKind.allCases {
            let output = try await engine.export(url: url, settings: settings, film: film, edge: 1600, kind: kind)
            defer { try? FileManager.default.removeItem(at: output) }
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 192); XCTAssertEqual(image.height, 192)
            XCTAssertNotNil(image.colorSpace)
            XCTAssertEqual(image.bitsPerComponent, kind == .png ? 16 : 8)
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
            XCTAssertEqual(exif[kCGImagePropertyExifPixelXDimension] as? Int, 192)
            XCTAssertEqual(exif[kCGImagePropertyExifPixelYDimension] as? Int, 192)
        }
        await engine.clear()
    }

    func testCatalogProfilesAndLicenseTextsShip() throws {
        let library = try FilmLibrary.load()
        XCTAssertGreaterThan(library.films.count, 20)
        let root = Bundle.main.bundleURL.appendingPathComponent("GrainroomData")
        for stock in library.stocks {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("engine/profiles/\(stock.id).json").path), stock.id)
        }
        for name in ["SpektraLab-GPL-3.0.txt", "Profiles-and-LUTs-CC-BY-SA-4.0.txt", "metal-cpp-Apache-2.0.txt", "PRODUCT_PROFILES_NOTICE.md"] {
            XCTAssertGreaterThan(try Data(contentsOf: root.appendingPathComponent("Licenses/\(name)")).count, 100)
        }
    }

    func testColorMonochromeAndPositiveStocksUseTheSameSession() async throws {
        let url = try DemoImage.make(width: 128, height: 96)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = try FilmProcessor(), library = try FilmLibrary.load()
        let choices = [try XCTUnwrap(library.stock("kodak_portra_400")),
                       try XCTUnwrap(library.films.first { $0.isMonochrome }),
                       try XCTUnwrap(library.films.first { $0.isPositive })]
        var settings = PhotoSettings(); settings.grain = 0; settings.halation = 0
        var previous: Data?
        for stock in choices {
            settings.film = stock.id
            settings.paper = stock.targetPrint ?? library.papers(for: stock).first!.id
            let result = try await engine.render(url: url, settings: settings, film: stock)
            XCTAssertEqual(result.width, 128); XCTAssertEqual(result.height, 96)
            let data = try XCTUnwrap(result.image.dataProvider?.data) as Data
            XCTAssertNotEqual(data, previous)
            previous = data
        }
        await engine.clear()
    }

    private func rgb(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let data = image.dataProvider!.data! as Data
        return data.withUnsafeBytes { bytes in
            (0..<3).map { Int(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: y * image.bytesPerRow + x * 8 + $0 * 2, as: UInt16.self))) }
        }
    }
}
