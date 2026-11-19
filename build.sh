#!/bin/zsh
# 編譯並打包成 build/Dock Usage.app：沒有 Dock 圖示的背景程式，在 Dock 裡的 Claude／ChatGPT 圖示上疊用量水位
#   ./build.sh            只打包
#   INSTALL=1 ./build.sh  另外覆蓋 /Applications
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=.build/release/UsageMeter
NAME="Dock Usage"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp $BIN "$APP/Contents/MacOS/DockUsage"
SET=$(mktemp -d)/AppIcon.iconset; mkdir -p $SET
$BIN --snapshot claude 40 - $SET/icon_512x512@2x.png 1024
for s in 16 32 128 256 512; do
  sips -z $s $s $SET/icon_512x512@2x.png --out $SET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) $SET/icon_512x512@2x.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $SET -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.dorara.dockusage</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>DockUsage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp=none --sign 40EE56946432E9A272F0B129ED83D5E843B5EAE8 "$APP"
if [ -n "$INSTALL" ]; then
  pkill -f "/Applications/$NAME.app/Contents/MacOS/DockUsage" || true
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
fi
echo built
