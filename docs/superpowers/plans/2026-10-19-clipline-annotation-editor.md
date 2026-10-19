# Clipline Annotation Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Reviews are internal under user AGENTS.md; continue without routine human approval.

**Goal:** Replace system Markup with a native editor matching the supplied TrarrenShot 1.5.3 interface and annotation tools.
**Architecture:** Keep Markup singleton entry/callback; pixel document and shared renderer power Canvas and export. Gestures commit snapshots; ImageIO provides safe output.
**Tech Stack:** Swift 5.9, macOS 14+, AppKit/CoreGraphics/CoreImage/ImageIO/Vision, no dependencies.

## Global Constraints

- Work only in /Users/wen/.codex/worktrees/clipline-annotation-editor/Tendedero, branch codex/annotation-editor. Filesystem writes here require formal exec require_escalated (native managed worktree outside initial roots). Do not touch installed app or push.
- Preserve Markup.shared.edit(_ url: URL) and onSaved: (URL) -> Void; preserve capture Cmd/Option/OCR and movie Trim.
- No packages or copied TrarrenShot code/assets; SF Symbols and own Clipline brand.
- Geometry uses EXIF-oriented source pixels and top-left origin. Export excludes selection controls, outside-crop pixels and original file URL.
- No source writes before explicit save. Reject changed/disappeared source or unsupported multi-frame overwrite; failures preserve source and editing session.
- Strings use L; English/Traditional Chinese authored, all other existing languages get matching English fallback entries.
- Behavioral assert tests in scripts/test.sh style; real red/green, generated fixtures only, no production test switches. Shell login:false, explicit workdir; Swift SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk.
- Commit only task files. Scope specification: docs/superpowers/specs/2026-10-19-clipline-annotation-editor.md.

### Task 1: Pixel document, complete renderer and safe output

**Files:** Create Sources/Clipline/AnnotationDocument.swift, AnnotationRenderer.swift, Tests/CliplineTests/AnnotationTests.swift, scripts/test-annotations.sh. Leave old Markup until integration.

**Interfaces:** AnnotationKind cases hand, rectangle, ellipse, line, arrow, text, bubble, pen, highlighter, pixelate, magnify, step, stamp, spotlight, note, eraser. AnnotationStyle equatable persistent tool options; Annotation stable UUID/kind/geometry/points/text/style/magnifier source; AnnotationState annotations/crop. @MainActor AnnotationDocument source CGImage/sourceURL/state/onChange closure, undo/redo/dirty, init(url:) throws, init(image:), commit(state:label:), undo(), redo(), render(includeNotes:) throws -> CGImage, saveOriginal() throws. AnnotationRenderer shared draw into existing CGContext plus render-to-CGImage, no full bitmap allocation per canvas draw. Exact field types/helper API may be chosen and must be documented in report.

- [ ] Add failing tests and record failure: add/delete/undo/redo/dirty, dynamic step numbering, asymmetric crop/orientation, PNG/JPEG actual UTI, transparent/P3 handling, reject missing/external-changed source, cancel zero writes.
- [ ] Implement snapshots bounded to 100; unchanged state no history. Preserve source bytes version/identity for conflict checks, original UTI/properties and EXIF normalization. Support ImageIO PNG/JPEG/TIFF/HEIC if encodable; reject animated/multipage overwrite. Clear stale orientation metadata. Private sibling temp and atomic replacement after recheck; cleanup on failures, never recreate deleted source.
- [ ] Renderer: square/rounded/dashed/filled boxes, ellipse, line, open/emphasis arrow; text/bubble and unclipped tail; pen/translucent highlighter; pixelate/blur/solid on prior composited content; magnifier independent source and zoom; steps, emoji; spotlight union cutouts; notes with numbered badge and solid/dashed/rounded/rounded-dashed frames or solid/dashed/curved arrows, export wrapped appendix. Source color space, exact crop, no handles.
- [ ] Add meaningful render assertions for overlapping Spotlight, three masks, magnifier source, crop dimensions/outside-color exclusion, wrapped notes, EXIF all 8 non-square patterns.
- [ ] Run scripts/test-annotations.sh, commit, write interface/test report. No UI claims.

### Task 2: Canvas, cropping and native text editing

**Files:** Create Sources/Clipline/AnnotationCanvas.swift, extend AnnotationTests.swift for geometry.
**Interfaces:** @MainActor AnnotationCanvas: NSView init(document: AnnotationDocument), tool/style/selectedID, selection/document callbacks and onFinish/onCancel/onCopy/onOCR. Expose selectTool, finishTextEditing, deleteSelection, duplicateSelection, applyStyle, undo/redo, fit/zoom/setCrop as needed. Read Task 1 code/report for exact model API, document final UI signatures.

- [ ] Red tests for coordinate conversion/reverse drag/Shift constraints/resize/crop clamp using production geometry helpers, not synthetic mouse events alone.
- [ ] Fit source-pixel image with room for toolbar; shared renderer draw then separate white crop border/8 handles and selected blue handles. Pan/zoom anchored to pointer. Avoid recomputing effects for hover; responsive large-image rendering.
- [ ] Creation for every tool; select topmost real geometry; move/resize points correctly; eraser removes annotations only; crop edges/move constrained to source; Shift lines at 45-degree/square; magnifier separate source handle when unlinked; one gesture one undo. Step/stamp click visible, other shape click-create configurable.
- [ ] NSTextView overlay for text/bubble/note, double-click edits. IME marked text and text shortcuts have priority. Esc text finish then deselect then close callback; Delete outside text removes selection; Cmd+D duplicate; Cmd+Z and Shift+Cmd+Z; Cmd+C selected text otherwise image; Space/Return finishes only outside text.
- [ ] Run tests/typecheck including canvas; commit and report UI/controller API plus native unverified list.

### Task 3: Floating toolbar, inspectors and Markup session

**Files:** Replace Markup.swift, create AnnotationToolbar.swift (split inspector if needed), localization files, Tests/CliplineTests/AnnotationHarness.swift, scripts/run-annotation-harness.sh. Read prior task interfaces.
**Interfaces:** Keep Markup.shared.edit(URL)/onSaved, expose requestClose() -> Bool for app termination. Controller owns document/window/output and dirty prompts.

- [ ] Dark editor, centered image, white crop border, floating rounded charcoal toolbar, blue active square, small dark parameter panel below. Order rectangle/ellipse/line/arrow/text+bubble/pen/highlighter/pixelate/magnify/step/stamp/spotlight/note/OCR/undo/redo/eraser/clear/share/save-as/copy/cancel; adjacent dimensions/settings/pin-shaped finish-to-original. Include hand mode, tooltips/AX labels, horizontal scrolling on narrow screens.
- [ ] All inspectors apply to selected object or new-tool style: width/color; rectangle 4 variants; arrow open/emphasis; text font/size/color and bubble background; pixelate 3 modes/intensity; magnify zoom/link; step colors/size; emoji field/search/system character palette; spotlight shape/radius/darkness; note seven variants. Native P3-capable color wells. Persist styles, last-tool/hand preference, small/large toolbar, click-create. Settings visibility/order/reset; close always reachable.
- [ ] Editable/collapsible notes overview, export includes notes once. Crop exact pixels, ratios 1:1/4:3/16:9, size presets 640x480/1280x720/1920x1080 clamped (explain no upsample). QR detection VNDetectBarcodesRequest, results list/copy/toggle hints; never open URL automatically.
- [ ] Async OCR existing Vision, Option uses DdddOCR; input rendered crop, selectable result, preserve clipboard blank/error. Cancel/close scopes cancellation; stale completion cannot alter next session.
- [ ] Copy/share/save-as use rendered image only; no original URL. PNG/JPEG save-as. Finish safely overwrites then onSaved exactly once. Close/Esc/otherURL/requestClose share Save/Discard/Cancel; save error leaves session open. SameURL just brings forward.
- [ ] Production-linked native harness uses generated non-private fixture and stable app ID/title; no production test flags, copy localizations. Report fixture/output location for CUA.
- [ ] Run tests/typecheck/string-check, commit. Report limits honestly.

### Task 4: Integration and release preparation

**Files:** AppDelegate.swift, Line.swift, scripts/test.sh/build-app.sh, README.md, docs/annotation-verification.md.
**Interfaces:** Markup.requestClose() -> Bool for applicationShouldTerminate. Existing callbacks and movie Trim unchanged.

- [ ] applicationShouldTerminate returns terminateCancel when dirty guard refuses, terminateNow after save/discard. Existing termination capture cancellation/Inbox restore unchanged.
- [ ] Add annotation test runner to scripts/test.sh, remove old system Markup wording, document controls/shortcuts/formats/flattened saved output. Bump app version 0.3.0 before final build.
- [ ] Run full tests, scripts/check-strings.swift, universal build with explicit SDKROOT, codesign --verify --deep --strict, lipo -archs. Record outcomes and native checks pending controller.
- [ ] Commit. Controller runs native acceptance/final independent review, then main branch integration, fork push, backup/install/restart and existing update automation preservation contract update.
