# Intro video

38 s, 1920×1080, 30 fps, with music and sound effects. Remotion composition in `src/Intro.tsx`; timing of every icon's fill lives in `src/tracks.json`. Section cuts sit on the music's bar lines (103.36 BPM, bar 0 = frame 105).

```sh
npm install
sh gen-frames.sh        # builds the app CLI, writes PNG sequences, plain icons and icon masks to public/gen/ (fake data only)
npx remotion render src/index.ts Intro out/raw.mp4 --crf=16       # English
npx remotion render src/index.ts IntroZh out/raw-zh.mp4 --crf=16  # 繁中字幕
# encode (same for -zh)
ffmpeg -y -i out/raw.mp4 -vf "scale=in_range=pc:out_range=tv,format=yuv420p" -color_range tv \
  -c:v libx264 -preset slow -crf 19 -profile:v high \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ar 48000 -c:a aac -b:a 160k -movflags +faststart ../site/assets/intro.mp4
# poster: no captions, shared by both languages
npx remotion still src/index.ts Poster out/poster.png --frame=675
ffmpeg -y -i out/poster.png -q:v 3 ../site/assets/intro-poster.jpg
```

Only the CLI's fake-data commands are used (`--frames`, `--fake-top`, `--fake-note`, `--appicon`). The filler Dock icons are drawn in CSS. Every overlay is clipped with the real icon's silhouette (`public/gen/mask/`), because the CLI's overlay corners are squarer than the icons.

## Audio sources

All from Mixkit, downloaded 2026-11-19. No attribution required.

- Music: [Mixkit Stock Music Free License](https://mixkit.co/license/#musicFree). Allowed in online marketing and web video. Not allowed on CDs/DVDs, in video games, in TV/radio broadcasts, as a remix or music-only track, or registered with Content ID.
- Sound effects: [Mixkit Sound Effects Free License](https://mixkit.co/license/#sfxFree). Commercial use allowed. Do not redistribute on their own.

| File in `public/audio/` | Mixkit item | Source |
|---|---|---|
| music-coffee-or-tea.mp3 | "Coffee or Tea" by Michael Ramir C. (#1168) | https://assets.mixkit.co/music/1168/1168.mp3 |
| sfx-air-woosh.wav | Air woosh (#1489) | https://assets.mixkit.co/active_storage/sfx/1489/1489.wav |
| sfx-small-sweep.wav | Fast small sweep transition (#166) | https://assets.mixkit.co/active_storage/sfx/166/166.wav |
| sfx-click-tone.wav | Cool interface click tone (#2568) | https://assets.mixkit.co/active_storage/sfx/2568/2568.wav |
| sfx-negative-tap.wav | Negative tone interface tap (#2569) | https://assets.mixkit.co/active_storage/sfx/2569/2569.wav |
| sfx-long-pop.wav | Long pop (#2358) | https://assets.mixkit.co/active_storage/sfx/2358/2358.wav |
| sfx-device-click.wav | Interface device click (#2577) | https://assets.mixkit.co/active_storage/sfx/2577/2577.wav |
| sfx-short-sweep.wav | Short transition sweep (#175) | https://assets.mixkit.co/active_storage/sfx/175/175.wav |
| sfx-light-pop.wav | Explainer video pops whoosh light pop (#3005) | https://assets.mixkit.co/active_storage/sfx/3005/3005.wav |
| sfx-interface-start.wav | Software interface start (#2574) | https://assets.mixkit.co/active_storage/sfx/2574/2574.wav |

Cue times and volumes are in the `CUES` list in `src/Intro.tsx`. The music starts 5.974 s into the track so its drums come in at frame 105.
