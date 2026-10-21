#!/bin/bash
set -e

echo "🔨 Building ScreenshotRenamer (Release)..."
swift build -c release

APP_NAME="ScreenshotRenamer.app"
CONTENTS_DIR="${APP_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "📦 Packaging ${APP_NAME}..."
mkdir -p "${MACOS_DIR}"
cp ".build/release/ScreenshotRenamer" "${MACOS_DIR}/ScreenshotRenamer"
cp "Info.plist" "${CONTENTS_DIR}/Info.plist"

# Ad-hoc codesign for local macOS execution
if command -v codesign &> /dev/null; then
    echo "🔏 Signing application..."
    codesign --force --deep --sign - "${APP_NAME}" 2>/dev/null || true
fi

echo "✅ Successfully built ${APP_NAME}"
echo "Run with: open ${APP_NAME}"
