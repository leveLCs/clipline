#!/bin/bash
# Build only: launch the resulting app through the native UI for acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
APP="$PWD/.build/annotation-harness/Clipline Annotation QA.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -o "$APP/Contents/MacOS/AnnotationQA" \
 Sources/Clipline/AnnotationDocument.swift Sources/Clipline/AnnotationRenderer.swift \
 Sources/Clipline/AnnotationCanvas.swift Sources/Clipline/AnnotationEditorSettings.swift \
 Sources/Clipline/AnnotationRecognition.swift Sources/Clipline/AnnotationToolbar.swift \
 Sources/Clipline/AnnotationInspector.swift Sources/Clipline/Markup.swift \
 Sources/Clipline/TextRecognition.swift Sources/Clipline/DdddOCR.swift \
 Sources/Clipline/Inbox.swift Sources/Clipline/Localization.swift \
 Tests/CliplineTests/AnnotationHarness.swift
cp -R Sources/Clipline/Resources/*.lproj "$APP/Contents/Resources/"
cp Sources/Clipline/Resources/ddddocr_worker.py "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.leveLCs.Clipline.AnnotationQA</string>
<key>CFBundleName</key><string>Clipline Annotation QA</string>
<key>CFBundleExecutable</key><string>AnnotationQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Harness: %s\nFixture (generated at launch): %s\n' "$APP" "$PWD/.build/annotation-harness/annotation-fixture.png"
