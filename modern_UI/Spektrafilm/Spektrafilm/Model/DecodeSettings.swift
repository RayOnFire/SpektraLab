// Shared RAW decode settings, extracted unchanged from Sidecar.swift for the iOS port.
// Derived from SpektraLab, GPL-3.0-or-later.
import Foundation

struct DecodeSettings: Codable, Equatable, Hashable, Sendable {
    enum WhiteBalance: String, Codable, CaseIterable, Sendable {
        case asShot = "As Shot", daylight = "Daylight", cloudy = "Cloudy", shade = "Shade",
             tungsten = "Tungsten", fluorescent = "Fluorescent", custom = "Custom"
        var kelvin: Double? {
            switch self {
            case .daylight: 5500
            case .cloudy: 6500
            case .shade: 7500
            case .tungsten: 3200
            case .fluorescent: 4000
            case .asShot, .custom: nil
            }
        }
    }
    var whiteBalance: WhiteBalance = .asShot
    /// Kelvin and tint actually applied at decode. For `.asShot` these are
    /// the camera's, filled in after the first decode; for presets the preset's.
    var temperature: Double = 5500
    var tint: Double = 0
    /// Apply the lens's own distortion and vignetting correction at decode.
    ///
    /// **A RAW-only decode setting, and deliberately not an engine
    /// parameter.** The PRD: "only RAW files can apply lens correction. If the
    /// RAW carries lens correction information already, i.e. Nikon NEFs,
    /// otherwise let core image handles it based on EXIF (the standard way)."
    /// That is `CIRAWFilter.isLensCorrectionEnabled` exactly — Core Image
    /// reads the manufacturer's own correction out of the file, and a file
    /// that does not carry one reports `isLensCorrectionSupported == false`,
    /// which is what greys the row rather than offering a switch that does
    /// nothing.
    ///
    /// Off by default: it changes the frame's geometry, and a crop or a
    /// straighten made before it was turned on would no longer describe the
    /// same rectangle.
    var lensCorrection: Bool = false
}
