// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct FilmStock: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let stage: String
    let type: String?
    let targetPrint: String?
    let monochrome: Bool?
    var isPositive: Bool { type == "positive" }
    var isMonochrome: Bool { monochrome ?? false }
}

struct FilmLibrary: Sendable {
    let stocks: [FilmStock]
    var films: [FilmStock] { stocks.filter { $0.stage == "filming" } }
    func stock(_ id: String) -> FilmStock? { stocks.first { $0.id == id } }
    func papers(for film: FilmStock?) -> [FilmStock] {
        stocks.filter { $0.stage == "printing" && $0.isMonochrome == (film?.isMonochrome ?? false) }
    }
    static func load() throws -> FilmLibrary {
        struct Catalog: Decodable { let stocks: [FilmStock] }
        guard let url = Bundle.main.url(forResource: "StockCatalog", withExtension: "json", subdirectory: "GrainroomData") else {
            throw PhotoFailure.message("胶片目录缺失，请按 README 重新构建项目。")
        }
        return FilmLibrary(stocks: try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).stocks)
    }
}

enum CropRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case original = "原比例", square = "1:1", portrait = "4:5", classic = "3:2", wide = "16:9"
    var id: String { rawValue }
    var ratio: Double? {
        switch self { case .original: nil; case .square: 1; case .portrait: 0.8; case .classic: 1.5; case .wide: 16.0 / 9.0 }
    }
}

struct PhotoSettings: Codable, Equatable, Sendable {
    var film = "kodak_portra_400"
    var paper = "kodak_portra_endura"
    var exposure = 0.0
    var printBrightness = 0.0
    var grain = 1.0
    var halation = 1.0
    var decode = DecodeSettings()
    var crop = CropRatio.original
    var quarterTurns = 0
    var mirror = false
}

enum PhotoFailure: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let value): value } }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
