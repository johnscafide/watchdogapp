#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Full Xcode with an iOS Simulator runtime is required.' >&2
  exit 1
fi
python3 Scripts/generate-project.py
python3 Scripts/check-source.py
swift test --package-path WatchdogCore
mkdir -p build
for family in iPhone iPad; do
  device_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); family=sys.argv[1]; matches=[x["udid"] for runtime,rows in d["devices"].items() if ".iOS-" in runtime for x in rows if x.get("isAvailable") and family in x["name"]]; print(matches[-1] if matches else "")' "$family")"
  if [[ -z "$device_id" ]]; then
    echo "Install an available $family iOS 17+ simulator in Xcode Settings > Platforms." >&2
    exit 1
  fi
  timestamp="$(date +%Y%m%d-%H%M%S)"
  xcodebuild test -project Watchdog.xcodeproj -scheme Watchdog -configuration Debug \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath build/DerivedData \
    -resultBundlePath "build/$family-$timestamp.xcresult" \
    CODE_SIGNING_ALLOWED=NO
done
xcodebuild build -project Watchdog.xcodeproj -scheme Watchdog -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ReleaseData CODE_SIGNING_ALLOWED=NO
echo 'Core tests, iPhone and iPad tests, and Release simulator build passed.'
