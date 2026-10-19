#!/bin/bash
# Run actual production code without requiring Xcode's XCTest framework.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
swiftc -parse-as-library -o .build/checks/capture-checks \
  Sources/Clipline/CaptureSelection.swift Sources/Clipline/TextRecognition.swift \
  Sources/Clipline/Inbox.swift Tests/CliplineTests/CaptureTests.swift
.build/checks/capture-checks
