#!/bin/zsh
# 上線一個新版本：改版號、commit、tag、push，從乾淨的副本做公證過的 DMG，發 GitHub Release，部署官網。
#   ./publish.sh 0.1.1 notes.md
# notes.md 是 release 說明（中英文）。只發已經 commit 的東西：工作目錄裡沒 commit 的改動不會進 DMG。
set -e
cd "${0:A:h}"
VERSION=$1 NOTES=${2:A}
[ -n "$VERSION" ] && [ -f "$NOTES" ] || { echo "usage: ./publish.sh <version> <notes.md>"; exit 1 }
git fetch -q && [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ] || { echo "main 跟 origin 不同步，先 pull／push"; exit 1 }

BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" -c "Set CFBundleVersion $BUILD" Resources/Info.plist
git add Resources/Info.plist
git commit -q -m "Dock Usage $VERSION

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git tag v$VERSION
git push -q origin main v$VERSION

W=$(mktemp -d)/dock-usage
git worktree add -q $W v$VERSION
trap "git worktree remove --force $W" EXIT
$W/release.sh
gh release create v$VERSION $W/build/DockUsage.dmg --title "Dock Usage $VERSION" --notes-file $NOTES
# 官網（dockusage.dorara.app）：下載鈕連 latest，所以 release 建好之後才部署
CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_AC_ID npx wrangler pages deploy $W/site --project-name dockusage --branch main --commit-dirty=true
