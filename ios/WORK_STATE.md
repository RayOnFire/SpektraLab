# Grainroom iOS work state

Authorized: implement an iPhone-first, offline single-photo editor derived from
SpektraLab. Publish source only in the user's GitHub fork. Users compile and
sign their own copies. App Store/TestFlight uploads and binary distribution
are outside scope.

Fork: RayOnFire/SpektraLab; upstream JamesQiu2005/SpektraLab at
02d82b56cf65f0f8e802a708612edc4e9a4790af. Work branch:
ios/grainroom-source-port. App name: Grainroom (independent unofficial port).

Verified before implementation: all 23 engine C++ translation units and all
8 engine Metal files compile for arm64 iOS 17 and Simulator; the canvas shader
also compiles. A 256x192 PNG completed the real Simulator decode, C ABI,
render, byte comparison, PNG round trip and UIKit display. Simulator needs
an output-texture copy with retained backing storage. Real-device RAW,
footprint, thermal behavior and high-resolution export remain unverified.

Implementation: add an iOS target alongside the macOS product. Reuse the
engine, shared decoder and source data. Cap preview before engine ingest;
render larger images only on explicit export. Include import from Photos and
Files, film/paper selection, exposure, grain, halation, RAW white balance,
center crop/rotation, JPEG/PNG export, saved editing state and license notices.

Verified implementation (2026-11-05; Xcode 27.1):

- `Grainroom` native Simulator tests: 6 tests, 0 failures, 0 skips. Runs the
  actual C++/Metal engine, not a mock. Checks changed pixels after parameter
  edits; color/monochrome/positive stocks in one session; PNG and HEIC bounded
  decode and EXIF rotation; top/bottom color placement across the C ABI;
  JPEG/16-bit PNG readback, pixel dimensions and EXIF dimensions; crop geometry;
  no upscaling/12 MP budget; all catalog profiles and bundled licenses.
- A first native edit test failed on `product_defaults` sent to `set_params`.
  Fixed the adapter to send this option only on open and send only changed
  fields thereafter. The same test then passed.
- Simulator install initially failed with "Missing bundle ID" despite a valid
  Info.plist. A minimal Bundle probe proved that a root `Resources` directory
  made it look like a legacy bundle. Use `GrainroomData` in the iOS bundle;
  installation, test launch and normal SwiftUI launch then succeeded.
- Actual app launched on iPhone 18 Pro Simulator and displayed a developed
  1200x900 synthetic color chart; a normal relaunch without the demo argument
  restored the saved photo and edit. This is an app launch/display check; the
  native tests drive the processor, not the Photos/Files/share-sheet UI.
- Unsigned arm64 device Release build succeeded, deployment target iOS 17.0.
  This proves compile/link and platform-specific Metal compilation, not
  physical-device behavior or signing/install.
- Shared macOS regression gate: 573 tests, 0 failures, 73 skipped. Missing
  camera/smoke fixtures and opt-in rendering checks are not covered. Do not
  call this a full camera parity run. Shared decoder's default path is kept.
- Engine `gpu_smoke`: 0 failures, safe-math probe, reductions, output texture
  and buffer/frame lifetimes passed on macOS. No compute kernels changed.
- Both project generators' `--check`, plist validation and `git diff --check`
  passed. Project/resources build without personal signing information.

Reproduce from the repository root using the commands in README.md. The macOS
gate uses `engine/build.sh bundle`, then `xcodebuild -project
modern_UI/Spektrafilm/Spektrafilm.xcodeproj -scheme SpektrafilmTests
-configuration Debug -derivedDataPath modern_UI/Spektrafilm/build/DerivedData
test`. Engine boundary: `engine/build.sh tests`, then `engine/build/gpu_smoke
engine/resources/spektrafilm.metallib`.

Pending device validation: Photos/Files and permission flows, share/save UI,
camera RAW/ProRAW, iOS 17 runtime, high-resolution exports, peak physical
footprint and sustained thermal behavior. iPhone takes priority over iPad.

Source delivery uses `ios/grainroom-source-port` in RayOnFire/SpektraLab.
No binary release or store upload. Next engineering task: validate the
documented import/export and memory limits on a physical iPhone.
