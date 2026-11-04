#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
swift build --disable-sandbox --product CamapMapKitCalibration
calibration_bin_dir="$(swift build --disable-sandbox --show-bin-path)"
calibration_app="$PWD/.build/MapKit对点校准.app"
mkdir -p "$calibration_app/Contents/MacOS"
cp -X "$calibration_bin_dir/CamapMapKitCalibration" "$calibration_app/Contents/MacOS/CamapMapKitCalibration"
cat > "$calibration_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.campura.camapkit.calibration</string>
<key>CFBundleName</key><string>MapKit对点校准</string>
<key>CFBundleExecutable</key><string>CamapMapKitCalibration</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Finder may add bundle metadata after a previous local launch; strip only
# FinderInfo/resource-fork metadata from this generated, ignored build artifact.
xattr -dr com.apple.FinderInfo "$calibration_app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$calibration_app" 2>/dev/null || true
codesign --force --sign - "$calibration_app"
printf '%s\n' "$calibration_app"
