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
- [x] Exercise the actual capture shortcut and both capture modes in the running app; the user confirmed OCR paste and Command-held hanging both work.
- [ ] Verify Esc preserves the clipboard, card restoration after reopening, multiple physical displays and full-screen Spaces in the running app.
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
- The user granted screen-recording access and opened region capture. The running app's full-screen overlay and Traditional Chinese mode instructions were visually verified. The UI driver then reported that the app state changed during its drag attempt, so that attempt did not establish either end-to-end result.
- The user subsequently tested both requested flows and explicitly confirmed "兩項都正常": Command-Shift-2 followed by a normal selection produces OCR text that can be pasted; holding Command until mouse-up hangs the screenshot at the top. This is user-confirmed native acceptance, separate from the automated core checks.
- Esc clipboard preservation, restoration after reopening, multiple physical displays and full-screen Spaces have not yet been verified in the running app.

## Option OCR update — 0.2.0 (2026-10-19)

- User requested default Apple Vision and Option-held ddddocr. Implemented mouse-up priority Command → Option → Vision, matching HUD and accessible instructions.
- Added private Python worker using ddddocr 1.6.1 default model, pipes only, telemetry disabled, JSON output validation, 15-second deadline and explicit cancellation. ddddocr keeps the selection overlay and Esc focus until finished. Both normal app termination and signal exit stop an active worker.
- Installer created a private CPython 3.13.9 plus pinned packages under Application Support/Clipline/OCR (365 MB). Its base interpreter is inside that directory, independent of pyenv, the repository and uv after installation. Runtime installation smoke test passed.
- Test-first checks initially failed on missing implementation, then the full final suite passed: 11 checks, zero failures. Coverage includes modifier priority, actual Vision/ ddddocr, blank output, invalid worker JSON, nonzero exit, missing runtime, timeout, SIGTERM-resistant worker, pre-launch and in-flight cancellation, private clipboard preservation and PNG storage. A wide-padding OCR fixture produced the same wrong output directly from the official model; the integration fixture now uses a tight single-line crop. This is not an accuracy improvement claim.
- All 76 localization keys match across 12 languages; shell syntax and git whitespace checks passed. Independent code review's cancellation-focus and test-prerequisite findings were resolved and reviewed again.
- Final universal release build and strict ad-hoc signature checks passed. Installed bundle reports 0.2.0 and executable SHA-256 `f203a0b1149d01fbfbd5b5a91f490b811cb8dcbdcd919969604413e7597c6970`, matching the build. Previous installed bundle is preserved at build/Clipline-0.1.0.backup.
- Installed app was relaunched from /Applications/Clipline.app; the login item remains enabled and allowed for the same path and bundle ID. The installed worker independently recognized a synthetic 1234 image in 0.352 seconds. No test workers remained.
- Native Option-drag, Command+Option priority gesture, waiting-state Esc and screen-recording permission after the updated signature remain unverified: the desktop driver times out when targeting the menu-bar-only app. Automated mode/process tests are not represented as native gesture acceptance. No new privacy permissions were granted automatically.
