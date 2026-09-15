#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null; then
  echo "Full Xcode with the iOS Simulator SDK is required." >&2
  exit 1
fi

# Keep the checked-in project synchronized with the source tree.
python3 Scripts/generate-project.py

rm -rf build/AppetizeData build/appetize
mkdir -p build/appetize

# Appetize requires an iOS Simulator .app bundle, not a device/App Store IPA.
# Debug is intentional: it matches Appetize's documented simulator-build flow
# and keeps Watchdog's optional --sample-data launch mode available for demos.
xcodebuild build \
  -project Watchdog.xcodeproj \
  -scheme Watchdog \
  -sdk iphonesimulator \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/AppetizeData \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO

APP_DIR="build/AppetizeData/Build/Products/Debug-iphonesimulator/Watchdog.app"
if [[ ! -d "$APP_DIR" ]]; then
  echo "Expected simulator app bundle was not found at $APP_DIR" >&2
  find build/AppetizeData/Build/Products -maxdepth 3 -type d -name '*.app' -print >&2 || true
  exit 1
fi

EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_DIR/Info.plist")"
echo "Built simulator executable:"
file "$APP_DIR/$EXECUTABLE"

# Preserve the .app directory as the top-level item inside the upload ZIP.
# This resulting file is what should be uploaded to Appetize.
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" build/appetize/Watchdog-Appetize.zip

echo "Appetize upload package: build/appetize/Watchdog-Appetize.zip"
