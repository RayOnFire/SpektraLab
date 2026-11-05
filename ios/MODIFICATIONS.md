# iOS port modifications — 2026-11-05

Grainroom is an unofficial source-only iOS port in RayOnFire/SpektraLab.
Base: JamesQiu2005/SpektraLab commit
`02d82b56cf65f0f8e802a708612edc4e9a4790af` (1.3.5, build 20).
Port code is GPL-3.0-or-later; existing copyright and separate data licenses
remain in effect. No endorsement by the upstream authors is implied.

- Added `ios/`: SwiftUI single-photo editor, C ABI actor adapter, local edit
  persistence, export, original icon artwork, Xcode project and native tests.
- Reused the existing 23 engine translation units, decoder, stock catalog and
  data resources. Metal sources are compiled with safe/precise math for each
  iOS platform. No compute kernels or spectral/material arrays were changed.
- Extracted `DecodeSettings` from `Sidecar.swift` without changing its format.
  The macOS project generator includes the extracted file.
- Added optional bounded decoding to `ImageDecoder`: ImageIO thumbnails for
  flat files and CIRAWFilter scale for RAW. The default remains unbounded for
  the desktop app. macOS half-frame composition stays macOS-only.
- Adapted the final output texture packaging only on Simulator: use a shared
  standalone texture and retain its backing buffer, because Simulator rejects
  the device's shared buffer-backed linear texture. Device and macOS use the
  original zero-copy path.
- Added fork-specific build/source-distribution documentation. The desktop
  app and historical documentation remain available in the fork.

The original 28 spektrafilm profiles and baked data are unchanged. Additional
SpektraLab product profiles are copied unchanged when building. Existing data
license and change-log files are bundled with their original content; their
desktop `Resources/engine` path corresponds to `GrainroomData/engine` in this
iOS bundle. See the About screen for the complete notices.
