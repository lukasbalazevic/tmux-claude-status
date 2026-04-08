#!/usr/bin/env bash
set -euo pipefail

# Claude must be running inside tmux
[ -n "${TMUX_PANE:-}" ] || exit 0

input="$(cat)"
event="$(jq -r '.hook_event_name // empty' <<<"$input")"
target_window="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}')"

set_waiting() {
  tmux set-option -wq -t "$target_window" @claude_done ""
  tmux set-option -wq -t "$target_window" @claude_waiting 1
}

set_done() {
  tmux set-option -wq -t "$target_window" @claude_waiting ""
  tmux set-option -wq -t "$target_window" @claude_done 1
  # Auto-clear after 10 seconds
  tmux run-shell -b -d 10 \
    "tmux set-option -wq -t '${target_window}' @claude_done ''; \
     tmux set-option -gq @claude_done_msg ''"
}

clear_all() {
  tmux set-option -wq -t "$target_window" @claude_waiting ""
  tmux set-option -wq -t "$target_window" @claude_done ""
}

case "$event" in
  Notification)
    ntype="$(jq -r '.notification_type // empty' <<<"$input")"
    case "$ntype" in
      permission_prompt|elicitation_dialog)
        set_waiting
        ;;
      idle_prompt)
        set_done
        ;;
      auth_success)
        ;;
    esac
    ;;
  PermissionRequest)
    set_waiting
    ;;
  Stop|StopFailure)
    set_done
    ;;
  UserPromptSubmit|PostToolUse|PostToolUseFailure)
    clear_all
    ;;
  SessionEnd)
    clear_all
    ;;
esac

# Build waiting status text (show window names for up to 2 windows)
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

# Recompute done aggregate
done_count="$(tmux list-windows -a -F '#{?@claude_done,1,0}' | awk '{s+=$1} END {print s+0}')"

if [ "$done_count" -gt 0 ]; then
  tmux set-option -gq @claude_done_msg 1
else
  tmux set-option -gq @claude_done_msg ""
fi
