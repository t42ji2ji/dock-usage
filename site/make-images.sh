#!/bin/zsh
# Regenerates every image on the site from the app itself, with made-up numbers only.
#   ./make-images.sh
# Needs: swift (builds the app), ImageMagick 7 (magick), ffmpeg with libwebp_anim.
# Doesn't touch assets/intro.mp4 or assets/intro-poster.jpg (rendered separately).
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT/site"
(cd "$ROOT" && swift build -c release >/dev/null)
B="$ROOT/.build/release/UsageMeter"
TMP="$ROOT/.build/site-frames"; rm -rf "$TMP"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT

# A bad argument makes the binary fall through and start the real app; cap every call at 60 s.
um() { perl -e 'alarm shift; exec @ARGV' 60 "$B" "$@"; }

# Seamless loop: the level stays put, the wave runs one full period (59 frames at 30 fps).
loop() {  # loop <out-name> <kind> <style> <level> [extra args]
  local name=$1 kind=$2 style=$3 lvl=$4; shift 4
  um --frames "$kind" "$style" "$lvl" "$lvl" 59 "$TMP/$name" 256 "$@"
  ffmpeg -loglevel error -y -framerate 30 -i "$TMP/$name/%04d.png" \
    -c:v libwebp_anim -lossless 0 -q:v 80 -loop 0 -pix_fmt yuva420p "assets/$name.webp"
}

loop claude      claude ascii 57 --attn 2
loop claude-red  claude ascii 86
loop gpt         gpt    ascii 38
loop finder      finder ascii 64
loop trash       trash  ascii 40
loop chrome      chrome ascii 35 --label 2.8h
for st in ascii liquid dots ring; do loop "look-$st" claude "$st" 62; done

um --fake-top  assets/top-sites.png
um --fake-note assets/note.png
um --snapshot claude 57 30 assets/hero.png 512 --attn 2

um --appicon assets/icon.png 1024
magick assets/icon.png -resize 32x32   favicon-32.png
magick assets/icon.png -resize 192x192 favicon-192.png
magick assets/icon.png -resize 180x180 apple-touch-icon.png

# 1200×630 share card: the app's dark gray, the icon, name and tagline in white
SF="/System/Library/Fonts/SFNS.ttf"
magick -size 1200x630 "xc:#0e0f0f" \
  \( assets/icon.png -resize 340x340 \) -gravity west -geometry +80+0 -composite \
  -font "$SF" -gravity northwest -fill white -pointsize 88 -annotate +470+210 "Dock Usage" \
  -fill "#8a8f8d" -pointsize 44 -annotate +474+330 "Your Dock, alive." \
  -fill "#5d6260" -pointsize 26 -annotate +476+440 "macOS · free and open source" \
  og-image.png

ls -la assets/*.webp assets/*.png favicon-*.png apple-touch-icon.png og-image.png | awk '{print $5, $NF}'
