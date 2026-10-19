# Clipline Capture Implementation Plan

**Goal:** 一個快捷鍵框選 OCR，按住 ⌘ 完成時掛圖。
**Architecture:** ScreenCaptureKit snapshot → AppKit selection → Vision text or existing Line.
**Tech Stack:** Swift 5.9 language mode, macOS 14+, AppKit, SwiftUI, Vision, ScreenCaptureKit; no dependencies.

## Constraints
使用者已授權完整實作；checkpoint 由主代理內部整合，不再請求使用者審核。程式碼保留 MIT 與來源，獨立名稱／圖示／bundle／資料目錄。OCR 圖片不落磁碟，失敗不清除剪貼簿。

## Tasks
- [x] Rename product/module/source path to Clipline, replace app branding and icon generator, remove upstream promotional artwork, retain LICENSE and attribution. Update scripts, translations, README and issue templates.
- [x] Add assert-based Swift tests first for CaptureSelection: opposite drag directions, negative display coordinates, 1×/2× pixels, clipped and empty selection, mouse-up Command routing. Add real Vision fixture and private pasteboard tests, plus PNG storage tests. Observe failures before implementing CaptureSelection.swift and TextRecognition.swift.
- [x] Add CaptureController.swift for one in-flight ScreenCaptureKit session, per-display snapshots and overlay windows. Implement native mouse/flags/Esc events, current-mode feedback, cancellation on display change, pixel crop, OCR completion and private PNG output.
- [x] Modify HotKey.swift to per-registration IDs. In AppDelegate.swift add capture action/menu/conflict retry; pass explicit source rect to existing hangCapture, suppress line while selecting, and reveal explicit captures over full screen. Independent code review covered shortcut dispatch/removal and capture cleanup.
- [x] Build with scripts/build-app.sh, run scripts/test.sh and scripts/check-strings.swift. Verify Info.plist, universal architectures and codesign.
- [ ] Exercise actual shortcuts, both capture modes and cancellation in the running app.
- [x] Commit/push reviewed source to the authorized fork, branch `codex/capture-ocr`.

## Verification commands
`scripts/test.sh`
`swift scripts/check-strings.swift`
`scripts/build-app.sh`
`codesign --verify --deep --strict --verbose=2 build/Clipline.app`
`lipo -archs build/Clipline.app/Contents/MacOS/Clipline`

Runtime checks: use synthetic visible Chinese/English fixture with native ⌘⇧2; verify OCR pasteboard output, Esc leaves pasteboard, Command-mouseUp creates a card and persisted PNG; reopen app to confirm card restoration. Do not silently change macOS privacy permissions or TextSniper shortcuts.

## Verification evidence (2026-10-19)

- Test-first baseline: eight failing checks with missing implementations; completed implementation: eight checks, zero failures.
- Tests use rendered synthetic Chinese/English images, a separate private pasteboard and disposable PNG files. Vision and pasteboard checks require access to normal macOS services outside the tool sandbox.
- All 70 localization keys match across 12 languages, including the new complete Traditional Chinese localization.
- Release app built for arm64 and x86_64; strict codesign verification passed with local ad-hoc signing.
- Independent source review found no blocking issue. Runtime event delivery, multiple physical displays and full-screen Spaces remain separate from geometry/unit-test coverage.
- The user granted screen-recording access and opened region capture. The running app's full-screen overlay and Traditional Chinese mode instructions were visually verified. The UI driver then reported that the app state changed during its drag attempt; neither an OCR clipboard result nor a hung screenshot was confirmed in that attempt. End-to-end OCR, Command-held hanging and Esc cancellation remain pending manual confirmation.
