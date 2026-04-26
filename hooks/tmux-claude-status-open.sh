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
term_app="${2:-iTerm}"
[ -n "$target_window" ] || exit 0
sess="${target_window%%:*}"

osascript -e "tell application \"${term_app}\" to activate" >/dev/null 2>&1 || true

if ! tmux has-session -t "=${sess}" 2>/dev/null; then
  osascript -e "display notification \"Session ${sess} no longer exists\" with title \"Claude Code\"" \
    >/dev/null 2>&1 || true
  exit 0
fi

if tmux switch-client -t "$target_window" 2>/dev/null; then
  exit 0
fi

open -na "$term_app" --args -e "tmux attach -t '$sess' \; select-window -t '$target_window'" \
  >/dev/null 2>&1 \
  || osascript -e "display notification \"Could not attach to ${target_window}\" with title \"Claude Code\"" \
       >/dev/null 2>&1 || true
