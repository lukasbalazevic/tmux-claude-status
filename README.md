# tmux-claude-status

See at a glance when [Claude Code](https://docs.anthropic.com/en/docs/claude-code) needs your attention — without switching tmux windows.

Uses Claude Code [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) to track two distinct states per window:

| State | Status bar | `prefix + w` |
|-------|-----------|--------------|
| **Waiting** — permission prompt or question | ![yellow badge](https://img.shields.io/badge/⚠_myapp_(main:2)-black?style=flat-square&labelColor=yellow) | `[Q]` red |
| **Done** — finished working | ![white badge](https://img.shields.io/badge/✓_Done-black?style=flat-square&labelColor=white) | `[✓]` cyan |
| **Working** — executing tools | _(empty)_ | _(no marker)_ |

The status bar shows the **window name** and **session:index** for up to 2 waiting windows. If 3 or more windows need attention, the first 2 are shown by name with a `+N` overflow badge. Use `prefix + w` to jump to any marked window.

```
1 window:   ⚠ myapp (main:2)
2 windows:  ⚠ myapp (main:2)  ⚠ server (work:0)
3 windows:  ⚠ myapp (main:2)  ⚠ server (work:0)  +1
```

The **Done** indicator auto-clears after 10 seconds.

## Requirements

- tmux 3.2+ (uses `run-shell -d`)
- `jq`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Install

### 1. Copy the hook script

```bash
cp hooks/tmux-claude-status.sh ~/.claude/hooks/tmux-claude-status.sh
chmod +x ~/.claude/hooks/tmux-claude-status.sh
```

### 2. Register Claude Code hooks

Merge the contents of `claude-hooks.json` into your `~/.claude/settings.json` (or `~/.claude/settings.local.json`):

```bash
# Quick look at what will be added
cat claude-hooks.json
```

If you already have a `"hooks"` key in your settings, merge the entries manually. Otherwise you can copy the block directly.

### 3. Add tmux configuration

Either source the config file:

```bash
# Add to ~/.tmux.conf
source-file /path/to/tmux-claude-status/tmux-claude-status.conf
```

Or copy the lines from `tmux-claude-status.conf` into your `~/.tmux.conf`.

### 4. Reload tmux

```bash
tmux source-file ~/.tmux.conf
```

## Customizing colors

The default colors are designed for a green tmux status bar (`bg=green,fg=black`). If your theme is different, edit the style tags in `tmux-claude-status.conf`.

**Status bar** — the waiting pills are built by the hook script in `tmux-claude-status.sh` (search for `#[bg=yellow]`). The done pill is in `tmux-claude-status.conf`. Change `bg=yellow` / `bg=white` to whatever contrasts with your bar.

**Choose-tree** (`prefix + w`) — change `fg=red` / `fg=cyan`:

```
#[fg=red]#[bold][Q]#[fg=default]#[nobold]
#[fg=cyan]#[bold][✓]#[fg=default]#[nobold]
```

> **Gotcha:** Don't use commas inside `#[...]` style tags (e.g. `#[fg=red,bold]`). Tmux's `#{?...}` conditional parser treats commas as delimiters. Use separate tags instead: `#[fg=red]#[bold]`.

## macOS notifications (optional)

Get a native banner — with sound, a tap target that switches your tmux client to the firing window, and auto-dismiss when you focus the pane manually.

### Install

```bash
brew install terminal-notifier
cp hooks/tmux-claude-status-open.sh  ~/.claude/hooks/
cp hooks/tmux-claude-status-clear.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/tmux-claude-status-*.sh
cp tmux-claude-status.config.example.json ~/.claude/hooks/tmux-claude-status.config.json
```

Then edit `~/.claude/hooks/tmux-claude-status.config.json` — set `terminal_app` to your terminal (`Ghostty`, `iTerm`, `Terminal`, `Alacritty`, …) and adjust copy / sound to taste.

The notifications are **opt-in by config presence**: without `tmux-claude-status.config.json`, or without `terminal-notifier` on `PATH`, the hook script behaves exactly like the upstream original — tmux pills only.

If you didn't already source the full `tmux-claude-status.conf`, add these two lines to `~/.tmux.conf` to enable auto-dismiss (`focus-events on` is required for `pane-focus-in` to actually fire):

```tmux
set -g focus-events on
set-hook -g pane-focus-in 'run-shell -b "~/.claude/hooks/tmux-claude-status-clear.sh \"#{session_name}:#{window_index}\""'
```

### Config

```json
{
  "terminal_app": "Ghostty",
  "suppress_when_focused": true,
  "waiting": {
    "title": "Claude Code",
    "subtitle": "⚠ {target_window}",
    "message": "Claude needs your input",
    "sound": "Ping"
  },
  "done": {
    "title": "Claude Code",
    "subtitle": "✓ {target_window}",
    "message": "Claude finished",
    "sound": "Glass"
  }
}
```

`suppress_when_focused` (default `true`) skips the banner when the configured terminal is already the macOS frontmost app **and** an attached tmux client is currently showing the originating window — i.e. you'd see the prompt anyway, no point in a banner. Set to `false` to always banner. Detection uses `lsappinfo` (no Accessibility permission required) plus `tmux list-clients` / `display-message`.

Templatable placeholders in `subtitle` / `message`: `{target_window}` (e.g. `main:2`), `{session}`, `{window_index}`.

Sounds: `Ping`, `Glass`, `Hero`, `Funk`, `Basso`, `Bottle`, `Frog`, `Morse`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`. Empty / omitted → silent banner.

### Tap behaviour

1. Foregrounds the configured `terminal_app` (always — even when the switch succeeds).
2. `tmux switch-client -t session:index` — retargets your already-attached tmux client across sessions/windows on the same tmux server.
3. **Fallback** when no client is attached: spawns a new terminal-app window via `open -na "$terminal_app" --args -e "tmux attach -t $session \; select-window -t $session:$index"`.
4. **Dead-session** (target killed since the banner fired): shows a "Session X no longer exists" notification instead of failing silently.

### Auto-dismiss

When you focus the originating pane via tmux without tapping the banner, the `pane-focus-in` hook clears the tmux flags and runs `terminal-notifier -remove "claude-$target_window"` to dismiss the Notification Center entry.

### Caveats

- **Multi-window tmux clients.** `switch-client` retargets the most-recently-active client, not a specific terminal-app window. If you run multiple tmux clients side-by-side, you can't pre-select which one switches.
- **Multi-server tmux.** Only works when your terminal-app's tmux client and Claude Code share a tmux server (same socket / user). Cross-server switches aren't possible.
- **Glance without focus.** `pane-focus-in` only fires on actual pane focus changes. If you switch to a *window* that already has a non-Claude pane focused, the auto-dismiss won't run — you'd need to focus the Claude pane explicitly. Banners do still clear when Claude itself emits `UserPromptSubmit` / `PostToolUse` after you engage.
- **Ghostty fallback opens a second instance.** Ghostty's AppleScript dictionary doesn't expose `do script`, so the no-client fallback uses `open -na` which spawns a new Ghostty process. iTerm / Terminal.app would not have this issue, but the script doesn't currently special-case them.

## How it works

The hook script receives JSON events from Claude Code and sets tmux window-level options:

- `@claude_waiting` — set when Claude needs user input (permission prompt, elicitation dialog)
- `@claude_done` — set when Claude finishes (stop, idle prompt). Auto-cleared after 10s via `tmux run-shell -b -d 10`

Global options drive the status bar:

- `@claude_waiting_text` — pre-styled status bar text showing waiting window names + session:index (up to 2, then `+N` overflow)
- `@claude_done_msg` — flag for showing the "Done" badge

### Event mapping

| Claude Code event | State |
|---|---|
| `Notification(permission_prompt)` | waiting |
| `Notification(elicitation_dialog)` | waiting |
| `PermissionRequest` | waiting |
| `Notification(idle_prompt)` | done |
| `Stop` / `StopFailure` | done |
| `UserPromptSubmit` | clear |
| `PostToolUse` / `PostToolUseFailure` | clear |
| `SessionEnd` | clear |

## License

MIT
