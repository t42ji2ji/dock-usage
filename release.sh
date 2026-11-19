#!/bin/zsh
# 做出可以給別人下載的 build/DockUsage.dmg：Developer ID 簽名、Apple 公證、staple。
# 公證用鑰匙圈裡的 notarytool 設定 away-blur（整個開發者帳號共用）
# DMG 檔名固定，README 的下載連結指向 releases/latest/download/DockUsage.dmg
set -e
cd "${0:A:h}"
DMG=build/DockUsage.dmg
RELEASE=1 ./build.sh
ditto -c -k --keepParent "build/Dock Usage.app" build/DockUsage.zip
xcrun notarytool submit build/DockUsage.zip --keychain-profile away-blur --wait --timeout 20m
xcrun stapler staple "build/Dock Usage.app"
rm build/DockUsage.zip
STAGE=build/dmg && rm -rf $STAGE && mkdir -p $STAGE
cp -R "build/Dock Usage.app" $STAGE/ && ln -s /Applications $STAGE/Applications
rm -f $DMG && hdiutil create -volname "Dock Usage" -srcfolder $STAGE -format UDZO -quiet $DMG
codesign --force --timestamp --sign 40EE56946432E9A272F0B129ED83D5E843B5EAE8 $DMG
xcrun notarytool submit $DMG --keychain-profile away-blur --wait --timeout 20m
xcrun stapler staple $DMG
spctl --assess --type open --context context:primary-signature -v $DMG
echo "done: $DMG"
