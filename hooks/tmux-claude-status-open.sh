#!/usr/bin/env bash
# Invoked by terminal-notifier -execute when a Claude banner is tapped.
# Args: $1 = target_window (session:index), $2 = terminal_app
#
# terminal-notifier's `-execute` runs via AppleScript `do shell script`,
# which uses a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). tmux usually
# lives in `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel),
# so prepend those to make it discoverable.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

set -uo pipefail

target_window="${1:-}"
term_app="${2:-Ghostty}"
[ -n "$target_window" ] || exit 0
sess="${target_window%%:*}"
idx="${target_window##*:}"

NOTIFY_CONFIG="${TMUX_CLAUDE_STATUS_CONFIG:-$HOME/.claude/hooks/tmux-claude-status.config.json}"

osascript -e "tell application \"${term_app}\" to activate" >/dev/null 2>&1 || true

if ! tmux has-session -t "=${sess}" 2>/dev/null; then
  osascript -e "display notification \"Session ${sess} no longer exists\" with title \"Claude Code\"" \
    >/dev/null 2>&1 || true
  exit 0
fi

if tmux switch-client -t "$target_window" 2>/dev/null; then
  exit 0
fi

# No-attached-client fallback. Read `spawn_command` from config; if absent,
# use the Ghostty-shaped default. Placeholders: {app} {session}
# {target_window} {window_index}. The rendered string is run via `sh -c` —
# users override per-terminal via the JSON config (see README for known-good
# values).
spawn_template=""
if [ -r "$NOTIFY_CONFIG" ] && command -v jq >/dev/null 2>&1; then
  spawn_template="$(jq -r '.spawn_command // ""' "$NOTIFY_CONFIG" 2>/dev/null)"
fi
if [ -z "$spawn_template" ]; then
  spawn_template='open -na {app} --args -e "tmux attach -t {session} \; select-window -t {target_window}"'
fi
spawn_cmd="$spawn_template"
spawn_cmd="${spawn_cmd//\{app\}/$term_app}"
spawn_cmd="${spawn_cmd//\{session\}/$sess}"
spawn_cmd="${spawn_cmd//\{target_window\}/$target_window}"
spawn_cmd="${spawn_cmd//\{window_index\}/$idx}"

/bin/sh -c "$spawn_cmd" >/dev/null 2>&1 \
  || osascript -e "display notification \"Could not attach to ${target_window}\" with title \"Claude Code\"" \
       >/dev/null 2>&1 || true
