# DEX//PROMPTENDER — Appearance Settings Visibility Repair

Baseline: GitHub main at e7bc1dc5d9177d4d7f68ad76c834d55f53b9817f.
Target: native macOS SwiftUI/AppKit DEX//PROMPTENDER.
Context: after installing the Impeccable release, the appearance controls appeared to do little or nothing.

## Verified source findings

- The appearance toggles/sliders used bindings to a shared AppearanceSettingsStore and persisted settings, but Settings offered no live visual preview.
- RootPopoverView placed a full-strength ultra-thin material layer above any custom backdrop image; the picture could be too obscured to evaluate opacity and blur.
- Unreadable or missing user-selected image paths silently fell back to a neutral background.
- Previous tests checked JSON persistence and static UI rendering; they did not assert that visible pixels changed.

## Bounded implementation

- Added PromptenderAppearanceLayer, the single renderer shared by The Bar and the Settings live preview.
- Added the 176-point live preview with foreground text samples; the user can see the effect while adjusting appearance controls.
- Reduced the image-obscuring material and introduced a color-scheme-appropriate foreground-protection scrim for readability with bright photos.
- Added actionable missing/unreadable image feedback; watermark still uses the bundled default when no custom path is supplied.
- Replaced the unverified SwiftUI image-layer blur path with a native Core Image Gaussian blur that produces inspectable pixels, respects the existing 0-28 slider, retains the original image unchanged, downscales input images to at most 1600 pixels, and caches limited output variants.
- Preserved appearance-settings JSON schema and local file location, watermark blend modes and scale, fit/fill, UI navigation, compiler, DexDiffusion, wildcard and Keychain behavior.

## Validation

- SwiftPM debug build: PASS.
- Swift Testing: **42/42** cases across eight suites PASS.
- Actual NSHostingView pixel comparisons verify opacity, tint, watermark on/off, watermark size, image fit/fill and blur changes using generated temporary vivid images.
- Tests prove missing-image states are explanatory; cached blur returns the reused image; source PNG bytes remain unchanged.
- Native Settings view snapshot with live preview was inspected offscreen; this does not equal actual MacBook click-through.
- Native release bundle built, Info.plist validated, arm64 executable verified, strict ad-hoc code-signature check passed, and bundled app launched/quit cleanly on Big Mac. Release executable SHA-256: 3229c5d1a8930bf671ff272ca7f1654a7ab3a18f6dbbad0df5b86fe6e9e791d7.

## Not yet proven

- Actual mouse/trackpad slider drags and VoiceOver behavior on MacBook Air: MacBook's remote execution permission is off.
- Full visual contrast measurements for every arbitrary user-provided background.
- Developer ID signing/notarization: this app is ad-hoc signed.

There were no calls to paid providers or destructive writes to live DexDiffusion wildcard banks.
