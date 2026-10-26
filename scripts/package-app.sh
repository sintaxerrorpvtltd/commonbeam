#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/swift-local.sh build -c release
app="dist/Commonbeam.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Commonbeam "$app/Contents/MacOS/Commonbeam"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.commonbeam.local-alpha</string>
<key>CFBundleName</key><string>Commonbeam</string>
<key>CFBundleExecutable</key><string>Commonbeam</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Local ad-hoc signing binds the completed bundle, without using a signing identity.
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf '%s\n' 'Built dist/Commonbeam.app (ad-hoc developer build; not notarized).'
