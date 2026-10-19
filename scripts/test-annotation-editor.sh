#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
swiftc -parse-as-library -o .build/checks/annotation-editor-checks \
 Sources/Clipline/AnnotationDocument.swift Sources/Clipline/AnnotationRenderer.swift \
 Sources/Clipline/AnnotationEditorSettings.swift Sources/Clipline/AnnotationRecognition.swift \
 Sources/Clipline/AnnotationCanvas.swift Sources/Clipline/AnnotationToolbar.swift \
 Sources/Clipline/AnnotationInspector.swift Sources/Clipline/Markup.swift \
 Sources/Clipline/TextRecognition.swift Sources/Clipline/DdddOCR.swift Sources/Clipline/Inbox.swift \
 Sources/Clipline/Localization.swift Tests/CliplineTests/AnnotationEditorTests.swift
.build/checks/annotation-editor-checks
