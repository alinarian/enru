#!/bin/bash
# Builds enru in release mode and packages it as a standalone enru.app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="enru"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/${APP_NAME}.icns" "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>enru</string>
    <key>CFBundleDisplayName</key>
    <string>enru</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.enru</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>enru</string>
    <key>CFBundleIconFile</key>
    <string>enru</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Code-signing (ad-hoc)..."
# An ad-hoc signature is required even for local, non-Store use: several system frameworks
# (including on-device Translation) talk to XPC services that refuse unsigned callers, and
# the request just hangs forever rather than returning an error.
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "Done: $(pwd)/${APP_BUNDLE}"
echo "Move it to /Applications, then double-click to launch (or open ${APP_BUNDLE})."
