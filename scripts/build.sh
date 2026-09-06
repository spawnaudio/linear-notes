#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Applications/Xcode-beta.app ]]; then export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer; fi
if [[ "${1:-}" == "--editor" ]]; then (cd Editor && npm ci --no-audit --no-fund && npm run build); fi
swift build -c release --scratch-path .build
APP="dist/Linear Notes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LinearNotes "$APP/Contents/MacOS/LinearNotes"
cp -R .build/release/LinearNotes_LinearNotes.bundle "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
