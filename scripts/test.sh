#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Applications/Xcode-beta.app ]]; then export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer; fi
swift test --scratch-path .build
