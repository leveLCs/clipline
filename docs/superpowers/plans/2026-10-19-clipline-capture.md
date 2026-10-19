# Clipline Capture Implementation Plan

**Goal:** 一個快捷鍵框選 OCR，按住 ⌃ Ctrl 完成時掛圖。

2026-10-20 更新：0.3.2 依使用者要求將掛圖修飾鍵由 Command 改為 Control；下方原始實作與驗收紀錄保留當時操作。現行行為以 README、CaptureMode 與最新回歸測試為準。
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

## 0.3.2 Ctrl 掛圖更新（2026-10-20）

- 將唯一共用的模式判斷改為 Control 優先於 Option；Command 不再掛圖。同步 12 語系的 HUD／選單／輔助使用提示與正體中文空白掛圖列。
- 新的按鍵案例在修改前重現 6 個失敗，修改後 11 capture/OCR、38 annotation checks 與 editor assertions 全通過；205 語系 keys 檢查通過。
- arm64／x86_64 建置完成，候選與原安裝版固定簽章相容。透過 NSRunningApplication.terminate 正常退出舊版後，備份並安裝 0.3.2；安裝版雜湊與候選相同，簽章與正式路徑啟動已確認。
- 每週上游同步契約已改為 Control 掛圖，並依使用者要求自行正常退出，不例行要求手動退出。
- 本機完整證據與 0.3.1 回復副本位於 build/control-hang-verification/。Ctrl 真實滑鼠拖曳尚未原生驗收；不以程式測試代替此項觀察。
