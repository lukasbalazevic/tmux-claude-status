# tmux-claude-status

See at a glance when [Claude Code](https://docs.anthropic.com/en/docs/claude-code) needs your attention — without switching tmux windows.

Uses Claude Code [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) to track two distinct states per window:

| State | Status bar | `prefix + w` |
|-------|-----------|--------------|
| **Waiting** — permission prompt or question | ![yellow badge](https://img.shields.io/badge/⚠_Claude:_1-black?style=flat-square&labelColor=yellow) | `[Q]` red |
| **Done** — finished working | ![white badge](https://img.shields.io/badge/✓_Done-black?style=flat-square&labelColor=white) | `[✓]` cyan |
| **Working** — executing tools | _(empty)_ | _(no marker)_ |

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

**Status bar** — change `bg=yellow` / `bg=white` to whatever contrasts with your bar:

```
#[bg=yellow]#[fg=black]#[bold] ⚠ Claude: #{@claude_waiting_count} #[default]
#[bg=white]#[fg=black]#[bold] ✓ Done #[default]
```

**Choose-tree** (`prefix + w`) — change `fg=red` / `fg=cyan`:

```
#[fg=red]#[bold][Q]#[fg=default]#[nobold]
#[fg=cyan]#[bold][✓]#[fg=default]#[nobold]
```

> **Gotcha:** Don't use commas inside `#[...]` style tags (e.g. `#[fg=red,bold]`). Tmux's `#{?...}` conditional parser treats commas as delimiters. Use separate tags instead: `#[fg=red]#[bold]`.

## How it works

The hook script receives JSON events from Claude Code and sets tmux window-level options:

- `@claude_waiting` — set when Claude needs user input (permission prompt, elicitation dialog)
- `@claude_done` — set when Claude finishes (stop, idle prompt). Auto-cleared after 10s via `tmux run-shell -b -d 10`

Global options drive the status bar:

- `@claude_waiting_count` — number of windows waiting for input
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
