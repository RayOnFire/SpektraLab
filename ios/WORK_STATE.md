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

## iPhone layout revision — 2026-11-05

Authorized: remove the preview frame/margins and allow film/paper selection
directly on the editor. Only the iOS view, documentation and own demo capture
change; shared engine/decoder and macOS sources are unchanged.

- Loaded preview keeps its aspect ratio, with no rounded mask, frame or
  horizontal inset. Metadata and controls keep readable margins.
- Film and paper are separate horizontal strips of buttons. The selected
  item is outlined/checked and scrolled into view. Choosing uses the existing
  model/render path; monochrome paper matching and positive-film behavior
  stay the same. Both stock-picker sheets were removed.
- iOS native integration suite: 6 passed, 0 failures/skips. Unsigned arm64
  device Release build passed. Reuse the earlier macOS gate because neither
  desktop build inputs nor shared engine/decoder sources changed.
- Actual Simulator display checked with a user-provided ProRAW: the loaded
  image fills the screen width and both stock strips are visible. Private
  input and its screenshot stay outside source control. This is display
  validation; native tests validate stock/render changes, not automated taps.
- Updated the public editor screenshot using the app's own synthetic chart
  in a separate Simulator, preserving the active photo and edits. The
  temporary preview Simulator was removed after capture.

Source delivery remains on the existing iOS branch. Physical-device
RAW/export/memory checks remain pending.

## Full-screen viewer and hold comparison — 2026-11-05

Authorized: collapse all editing regions for full-screen photo viewing,
pinch zoom/pan, and temporarily show the original while holding the image.

- Tap the preview or Full Screen button to open a separate full-screen
  surface. Editing regions and navigation/status bars are hidden, with system
  overlays requested hidden. View controls auto-hide; tap to reveal the exit
  button.
- UIKit UIScrollView provides 1–8x pinch zoom and pan. Double-tap zooms in or
  returns to fit. Rotation fits the whole image to the new viewport.
- Editor and viewer share PhotoViewport. A 0.25-second one-finger hold swaps
  the already cached UIImage to the original. Release, cancellation, scene
  interruption and view removal restore the applied image. Comparison
  preserves the same zoom/offset; pinch cancels comparison. No render is
  requested by these display gestures. Removed persistent original toggle.
- Added native view checks for image fitting/rotation, zoom/offset agreement,
  comparison release/cancellation, pinch interruption, and inline scroll
  behavior. Added a separate UI test target for full-screen entry, real pinch,
  long press/release, double-tap reset and return to editor. Test screenshots
  use only the app's own synthetic image on an isolated Simulator.
- Gates passed: 10 native tests plus 1 UI gesture test, 0 failures/skips;
  unsigned arm64 device Release build; actual editor/full-screen screenshot
  inspection; deterministic project/diff checks. Shared engine/decoder and
  macOS build inputs are unchanged; reuse the earlier desktop/engine gates.
- The first fitting test used subpixel accuracy for a pixel-rounded scroll
  offset; the tolerance now follows display pixel size. The UI test checks
  that editor controls cannot be hit under the modal surface; existence in
  XCTest's hierarchy alone is not a visibility/interaction check.

Demo screenshots updated from the running app. Installed the verified app on
the user's Simulator preserving their current edit. The same real UI gesture
case also passed with the user's existing ProRAW; its screenshots are kept
outside source control. Source delivery stays on the existing iOS branch.

## Save-to-Photos crash — 2026-11-05

Authorized: fix the crash when saving an exported photo to Photos and update
the user's Simulator. Source-only delivery remains in effect.

Crash evidence: SIGTRAP on `com.apple.PHPhotoLibrary.transaction.high`, in
`EditorModel.saveToPhotos`'s change block through `_swift_task_checkIsolatedSwift`
and `_dispatch_assert_queue_fail`. The block inherits MainActor isolation from
EditorModel but Photos executes it on its own queue. The photo-add usage
description is present; the failure is after export, inside the real write.

Fixed the change block with explicit `@Sendable`, capturing only the file URL.
Photos can run the block on its queue, while the UI success/error update
continues on MainActor after await.

Added a UI regression using the app's own synthetic image on an isolated
Simulator. It generates the JPEG, taps Save to Photos, handles the add-only
authorization prompt and waits for transaction completion. It refuses a
restored non-demo photo as input. The original callback reproduced the crash;
the fixed callback passed. Photos storage contains a new 1200x900 JPEG that
matches the exported file byte-for-byte. Unsigned arm64 Release build and
project/diff checks passed. Prior viewer/native/desktop gates remain valid:
their production inputs did not change.

Installed the fix on the user's Simulator preserving the current photo/edit.
Source delivery continues on the same iOS branch; no binary/store release.
