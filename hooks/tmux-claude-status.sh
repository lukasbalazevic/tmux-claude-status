#!/usr/bin/env bash
set -euo pipefail

# Claude must be running inside tmux
[ -n "${TMUX_PANE:-}" ] || exit 0

input="$(cat)"
event="$(jq -r '.hook_event_name // empty' <<<"$input")"
target_window="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}')"

NOTIFY_CONFIG="${TMUX_CLAUDE_STATUS_CONFIG:-$HOME/.claude/hooks/tmux-claude-status.config.json}"
NOTIFY_OPEN_SCRIPT="${TMUX_CLAUDE_STATUS_OPEN:-$HOME/.claude/hooks/tmux-claude-status-open.sh}"

notify() {
  [ -r "$NOTIFY_CONFIG" ] || return 0
  command -v terminal-notifier >/dev/null 2>&1 || return 0
  [ -x "$NOTIFY_OPEN_SCRIPT" ] || return 0

  local kind="$1"
  local cfg
  cfg="$(jq -c --arg k "$kind" '.[$k] // empty' "$NOTIFY_CONFIG" 2>/dev/null)" || return 0
  [ -n "$cfg" ] || return 0

  local sess="${target_window%%:*}"
  local idx="${target_window##*:}"
  local term_app
  term_app="$(jq -r '.terminal_app // "iTerm"' "$NOTIFY_CONFIG" 2>/dev/null)"

  render() {
    local t="$1"
    t="${t//\{target_window\}/$target_window}"
    t="${t//\{session\}/$sess}"
    t="${t//\{window_index\}/$idx}"
    printf '%s' "$t"
  }

  local title subtitle message sound
  title="$(render   "$(jq -r '.title    // "Claude Code"' <<<"$cfg")")"
  subtitle="$(render "$(jq -r '.subtitle // ""'           <<<"$cfg")")"
  message="$(render  "$(jq -r '.message  // ""'           <<<"$cfg")")"
  sound="$(jq -r '.sound // ""' <<<"$cfg")"

  local args=(
    -title   "$title"
    -message "$message"
    -group   "claude-${target_window}"
    -execute "${NOTIFY_OPEN_SCRIPT} '${target_window}' '${term_app}'"
  )
  [ -n "$subtitle" ] && args+=( -subtitle "$subtitle" )
  [ -n "$sound" ]    && args+=( -sound    "$sound"    )

  terminal-notifier "${args[@]}" >/dev/null 2>&1 || true
}

set_waiting() {
  tmux set-option -wq -t "$target_window" @claude_done ""
  tmux set-option -wq -t "$target_window" @claude_waiting 1
  notify waiting
}

set_done() {
  tmux set-option -wq -t "$target_window" @claude_waiting ""
  tmux set-option -wq -t "$target_window" @claude_done 1
  notify done
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
