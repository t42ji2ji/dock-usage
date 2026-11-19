<div align="center">

<img src="docs/icon.png" width="112" alt="Dock Usage app icon">

# Dock Usage

Your Claude and ChatGPT usage, drawn right on their Dock icons.

[**Download**](https://github.com/t42ji2ji/dock-usage/releases/latest/download/DockUsage.dmg) · [中文](README.zh-TW.md)

<img src="docs/claude.png" width="160" alt="Claude icon at 57%"> <img src="docs/chatgpt.png" width="160" alt="ChatGPT icon at 38%">

</div>

## What it shows

Each icon fills from the bottom as you use up your **5-hour limit**. The number in the middle is the percentage. Two small ticks on the sides mark your **weekly limit**. Past 80% it turns red. Pick one of four looks: flickering ASCII characters, liquid in glass, an LED dot matrix, or a glowing edge.

- **Claude** shows your Claude plan limits, read from Claude Code.
- **ChatGPT** shows your Codex limits on your ChatGPT plan, read from Codex.

Numbers update whenever you use Claude Code or Codex. A limit that has passed its reset time drops back to 0.

### Finder and the Trash

The Finder icon fills up as your disk does, with the percentage on top. The Trash fills up with how many things are in it, and is full at 30.

### Time in your browser

Chrome, Arc, Edge, Brave and ego lite icons fill up with how long you have used them today, full at 8 hours. Rest the pointer on one to see your top five sites. It reads the time each page stayed in front from the browser's own history, and only counts today.

### Latest notification on hover

Rest the pointer on an app in the Dock to see the last notification it showed you, such as a LINE message. It clears once you open that app. Only notifications that appeared on screen while Dock Usage was running are kept, and only in memory.

### Red dot for Claude Code sessions in cmux

If you run Claude Code in [cmux](https://cmux.com), a red dot with a count appears at the top right of the Claude icon (top left if Claude shows its own badge). It counts the tabs that show a notification in cmux: a session finished its turn, asks for permission, or waits for your input. It goes away once you open those tabs. Nothing to set up.

## Install

1. Download [DockUsage.dmg](https://github.com/t42ji2ji/dock-usage/releases/latest/download/DockUsage.dmg) and drag Dock Usage into Applications.
2. Open it. A short welcome walks you through allowing **Accessibility** (to find where icons sit in your Dock), picking what to show, and choosing a look. It restarts by itself once you allow access.
3. Keep the apps you want to see in your Dock (running or pinned).

Dock Usage has no Dock icon of its own and starts at login. Open it again from Applications to change what it shows, switch looks, or quit. Browser time and notifications read private data, so they stay off until you turn them on.

Requires macOS 14 or later on Apple Silicon.

### Claude: connect Claude Code

Claude Code passes your plan limits to its [status line](https://code.claude.com/docs/en/statusline) command. Dock Usage reads them from `~/.claude/dock-usage/claude.json`.

If you don't have a status line yet, the welcome screen sets one up for you. If you already have one, add these lines right after your script reads its input into `$input`:

```sh
mkdir -p "$HOME/.claude/dock-usage"
printf '%s' "$input" > "$HOME/.claude/dock-usage/claude.json.$$" && mv -f "$HOME/.claude/dock-usage/claude.json.$$" "$HOME/.claude/dock-usage/claude.json"
```

Requires a Claude Pro or Max plan.

### ChatGPT: nothing to set up

Codex writes your limits into its session logs under `~/.codex/sessions`. Dock Usage reads the latest one.

## Privacy

Dock Usage only reads those two local files, plus the notification list from cmux if you have it the notification banners shown on screen, and today's visits from ego lite and Chrome history. It never goes online and never touches your login tokens.

## Limits

- The ⌘Tab switcher shows the plain icons. Only the Dock is covered.
- The overlay follows the Dock as it slides in or magnifies, and can trail it by a frame.

## Build from source

Requires Xcode 16 command line tools.

```sh
./build.sh        # builds "build/Dock Usage.app"
```

Replace the signing identity in `build.sh` and `release.sh` with your own.

## Thanks

Inspired by [IconSwapper](https://iconswapper.app/), which shows live info on Dock icons. Dock Usage is a separate, open-source take on the idea for AI usage and everyday Mac stats.

## License

GPL-3.0. Claude and ChatGPT are trademarks of Anthropic and OpenAI. Dock Usage is not affiliated with either.
