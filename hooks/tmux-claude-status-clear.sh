#!/usr/bin/env bash
# Invoked from a tmux `pane-focus-in` hook. If the focused pane belongs to a
# window flagged as @claude_waiting / @claude_done, clear those flags, rebuild
# the global status text, and dismiss any matching macOS banner.
#
# Defensive PATH for environments where tmux/terminal-notifier aren't on the
# default PATH (mirrors the open script — same minimal-shell concern applies
# if this is ever invoked from an AppleScript context).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

set -uo pipefail

# When invoked from a tmux hook, tmux does NOT propagate $TMUX_PANE — but it
# does expand format specifiers, so the hook passes target_window as $1.
# When invoked directly from a shell (manual/test), fall back to $TMUX_PANE.
target_window="${1:-}"
if [ -z "$target_window" ]; then
  [ -n "${TMUX_PANE:-}" ] || exit 0
  target_window="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}' 2>/dev/null)" || exit 0
fi
[ -n "$target_window" ] || exit 0

waiting="$(tmux show-options -wqv -t "$target_window" @claude_waiting 2>/dev/null || true)"
done_v="$(tmux show-options -wqv -t "$target_window" @claude_done 2>/dev/null || true)"
[ -z "$waiting" ] && [ -z "$done_v" ] && exit 0

tmux set-option -wq -t "$target_window" @claude_waiting ""
tmux set-option -wq -t "$target_window" @claude_done ""

text=""
shown=0
total=0
while IFS='|' read -r sess name; do
  [ -z "$sess" ] && continue
  total=$((total + 1))
  if [ "$shown" -lt 2 ]; then
    text="${text}#[bg=yellow]#[fg=black]#[bold] ⚠ ${name} (${sess}) #[default] "
    shown=$((shown + 1))
  fi
done < <(tmux list-windows -a -F '#{?@claude_waiting,#{session_name}:#{window_index}|#{window_name},}')

remaining=$((total - shown))
if [ "$remaining" -gt 0 ]; then
  text="${text}#[bg=yellow]#[fg=black]#[bold] +${remaining} #[default] "
fi
tmux set-option -gq @claude_waiting_text "$text"

done_count="$(tmux list-windows -a -F '#{?@claude_done,1,0}' | awk '{s+=$1} END {print s+0}')"
if [ "$done_count" -gt 0 ]; then
  tmux set-option -gq @claude_done_msg 1
else
  tmux set-option -gq @claude_done_msg ""
fi

if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -remove "claude-${target_window}" >/dev/null 2>&1 || true
fi
