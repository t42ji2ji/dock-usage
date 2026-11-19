<div align="center">

<img src="docs/icon.png" width="112" alt="Dock Usage app icon">

# Dock Usage

Your Claude and ChatGPT usage, drawn right on their Dock icons.

[**Download**](https://github.com/t42ji2ji/dock-usage/releases/latest/download/DockUsage.dmg) · [中文](README.zh-TW.md)

<img src="docs/claude.png" width="160" alt="Claude icon at 57%"> <img src="docs/chatgpt.png" width="160" alt="ChatGPT icon at 38%">

</div>

## What it shows

A grid of flickering ASCII characters fills each icon from the bottom as you use up your **5-hour limit**. The number in the middle is the percentage. Two small ticks on the sides mark your **weekly limit**. Past 80% the characters turn red.

- **Claude** shows your Claude plan limits, read from Claude Code.
- **ChatGPT** shows your Codex limits on your ChatGPT plan, read from Codex.

Numbers update whenever you use Claude Code or Codex. A limit that has passed its reset time drops back to 0.

## Install

1. Download [DockUsage.dmg](https://github.com/t42ji2ji/dock-usage/releases/latest/download/DockUsage.dmg) and drag Dock Usage into Applications.
2. Open it and allow it in **System Settings › Privacy & Security › Accessibility**. It needs this to find where the icons sit in your Dock. If nothing shows up right after allowing, quit and open it again.
3. Keep the Claude and ChatGPT apps in your Dock (running or pinned).

Dock Usage has no window and no Dock icon of its own. It starts at login. Open it again from Applications to quit it or to turn off opening at login.

Requires macOS 14 or later on Apple Silicon.

### Claude: one line in your status line

Claude Code passes your plan limits to its [status line](https://code.claude.com/docs/en/statusline) command. Dock Usage reads them from `~/.claude/dock-usage/claude.json`, so the status line needs to save them there.

If you already have a status line script, add this right after it reads its input into `$input`:

```sh
rl=$(echo "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$rl" ]; then
  mkdir -p "$HOME/.claude/dock-usage"
  echo "$rl" > "$HOME/.claude/dock-usage/claude.json.$$" && mv -f "$HOME/.claude/dock-usage/claude.json.$$" "$HOME/.claude/dock-usage/claude.json"
fi
```

If you don't have one, save the lines above in `~/.claude/dock-usage.sh` with `input=$(cat)` as the first line, and add this to `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "sh ~/.claude/dock-usage.sh" }
```

Requires `jq` (`brew install jq`) and a Claude Pro or Max plan.

### ChatGPT: nothing to set up

Codex writes your limits into its session logs under `~/.codex/sessions`. Dock Usage reads the latest one.

## Privacy

Dock Usage only reads those two local files. It never goes online and never touches your login tokens.

## Limits

- The ⌘Tab switcher shows the plain icons. Only the Dock is covered.
- The overlay follows the Dock as it slides in or magnifies, and can trail it by a frame.

## Build from source

Requires Xcode 16 command line tools.

```sh
./build.sh        # builds "build/Dock Usage.app"
```

Replace the signing identity in `build.sh` and `release.sh` with your own.

## License

GPL-3.0. Claude and ChatGPT are trademarks of Anthropic and OpenAI. Dock Usage is not affiliated with either.
