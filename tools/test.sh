#!/bin/bash
# Compiles the real source files together with the assertions and runs them. No test target,
# because a hand generated pbxproj with a second target is more fragile than it is worth.
set -e
cd "$(dirname "$0")/.."
xcrun swiftc -target arm64-apple-macos14.0 -swift-version 6 -O \
  Sill/Store/DateParser.swift \
  Sill/Intelligence/IntelligenceBridge.swift \
  Tests/main.swift \
  -o build/logictests
./build/logictests
