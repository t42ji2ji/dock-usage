#!/bin/zsh
# 編譯並打包成 build/Claude Meter.app、build/GPT Meter.app（同一支執行檔，Info.plist 的 MeterKind 決定顯示哪家）
#   ./build.sh            只打包
#   INSTALL=1 ./build.sh  另外覆蓋 /Applications 並重開
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=.build/release/UsageMeter
VERSION=0.1.0
mkdir -p build
for KIND in claude gpt; do
  if [ $KIND = claude ]; then NAME="Claude Meter"; else NAME="GPT Meter"; fi
  APP="build/$NAME.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp $BIN "$APP/Contents/MacOS/UsageMeter"
  # Finder／沒在跑時的圖示：原 app 圖示＋示意水位
  SET=$(mktemp -d)/AppIcon.iconset; mkdir -p $SET
  $BIN --snapshot $KIND 40 - $SET/icon_512x512@2x.png 1024
  for s in 16 32 128 256 512; do
    sips -z $s $s $SET/icon_512x512@2x.png --out $SET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) $SET/icon_512x512@2x.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $SET -o "$APP/Contents/Resources/AppIcon.icns"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.dorara.meter.$KIND</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>UsageMeter</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>MeterKind</key><string>$KIND</string>
</dict></plist>
PLIST
  codesign --force --options runtime --timestamp=none --sign 40EE56946432E9A272F0B129ED83D5E843B5EAE8 "$APP"
  if [ -n "$INSTALL" ]; then
    pkill -f "/Applications/$NAME.app/Contents/MacOS/UsageMeter" || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/"
  fi
done
echo built
