#!/bin/zsh
# 編譯並打包成 build/Dock Usage.app：沒有 Dock 圖示的背景程式，在 Dock 裡的 Claude／ChatGPT 圖示上疊用量
#   ./build.sh             開發版（Developer ID 簽，權限不會每次重編都掉）
#   RELEASE=1 ./build.sh   發佈版：再加 hardened runtime＋時間戳（release.sh 用）
#   INSTALL=1 ./build.sh   另外覆蓋 /Applications
set -e
cd "${0:A:h}"
swift build -c release
BIN=.build/release/UsageMeter
APP="build/Dock Usage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp $BIN "$APP/Contents/MacOS/DockUsage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
SET=$(mktemp -d)/AppIcon.iconset; mkdir -p $SET
$BIN --appicon $SET/icon_512x512@2x.png 1024
for s in 16 32 128 256 512; do
  sips -z $s $s $SET/icon_512x512@2x.png --out $SET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) $SET/icon_512x512@2x.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $SET -o "$APP/Contents/Resources/AppIcon.icns"
ID=40EE56946432E9A272F0B129ED83D5E843B5EAE8
if [ -n "$RELEASE" ]; then
  codesign --force --options runtime --timestamp --sign $ID "$APP"
  codesign --verify --deep --strict "$APP"
else
  codesign --force --options runtime --timestamp=none --sign $ID "$APP"
fi
if [ -n "$INSTALL" ]; then
  pkill -f "/Applications/Dock Usage.app/Contents/MacOS/DockUsage" || true
  rm -rf "/Applications/Dock Usage.app"
  cp -R "$APP" /Applications/
fi
echo "built $APP"
