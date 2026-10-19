#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
swiftc -parse-as-library -o .build/checks/annotation-checks \
  Sources/Clipline/AnnotationDocument.swift Sources/Clipline/AnnotationRenderer.swift Sources/Clipline/AnnotationCanvas.swift \
  Sources/Clipline/Localization.swift Tests/CliplineTests/AnnotationTests.swift
.build/checks/annotation-checks
