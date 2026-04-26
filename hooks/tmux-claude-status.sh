#!/usr/bin/env bash
set -euo pipefail

# Claude must be running inside tmux
[ -n "${TMUX_PANE:-}" ] || exit 0

input="$(cat)"
event="$(jq -r '.hook_event_name // empty' <<<"$input")"
target_window="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}')"

NOTIFY_CONFIG="${TMUX_CLAUDE_STATUS_CONFIG:-$HOME/.claude/hooks/tmux-claude-status.config.json}"
NOTIFY_OPEN_SCRIPT="${TMUX_CLAUDE_STATUS_OPEN:-$HOME/.claude/hooks/tmux-claude-status-open.sh}"
DEBUG_LOG="${TMUX_CLAUDE_STATUS_LOG:-/tmp/tmux-claude-status.log}"

# Debug logging — gated by `"debug": true` in the JSON config OR by setting
# TMUX_CLAUDE_STATUS_DEBUG=1. Off by default. Includes PID + millisecond
# timestamps so concurrent hook invocations (a likely cause of double-fire)
# are visible.
DEBUG_ENABLED=0
if [ "${TMUX_CLAUDE_STATUS_DEBUG:-0}" = "1" ]; then
  DEBUG_ENABLED=1
elif [ -r "$NOTIFY_CONFIG" ] && [ "$(jq -r '.debug // false' "$NOTIFY_CONFIG" 2>/dev/null)" = "true" ]; then
  DEBUG_ENABLED=1
fi
_ts() {
  # macOS BSD date lacks %N. Prefer gdate (Homebrew coreutils) for ms; fall
  # back to second precision so the diagnostic still works on a vanilla mac.
  if command -v gdate >/dev/null 2>&1; then
    gdate +%Y-%m-%dT%H:%M:%S.%3N
  else
    date +%Y-%m-%dT%H:%M:%S
  fi
}
log() {
  [ "$DEBUG_ENABLED" = "1" ] || return 0
  printf '%s pid=%s %s\n' "$(_ts)" "$$" "$*" >> "$DEBUG_LOG" 2>/dev/null || true
}

is_user_focused() {
  # True when (a) the configured terminal app is the macOS frontmost app
  # AND (b) some attached tmux client's currently-shown window equals
  # target_window. Together: the user is already looking at the prompt.
  local term_app="$1"
  command -v lsappinfo >/dev/null 2>&1 || return 1

  local front_asn front_name
  front_asn="$(lsappinfo front 2>/dev/null)"
  [ -n "$front_asn" ] || return 1
  front_name="$(lsappinfo info -only name "$front_asn" 2>/dev/null \
                | sed -E 's/.*"([^"]+)"$/\1/')"
  [ "$front_name" = "$term_app" ] || return 1

  local clients
  clients="$(tmux list-clients -F '#{client_name}' 2>/dev/null)" || return 1
  local c cw
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    cw="$(tmux display-message -t "$c" -p '#{session_name}:#{window_index}' 2>/dev/null || true)"
    [ "$cw" = "$target_window" ] && return 0
  done <<< "$clients"
  return 1
}

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

  # When `suppress_when_focused` is true (default), skip the banner if the
  # user is already on the originating Claude pane in the foreground
  # terminal. Set to false to always banner.
  local suppress
  suppress="$(jq -r '.suppress_when_focused // true' "$NOTIFY_CONFIG" 2>/dev/null)"
  if [ "$suppress" = "true" ] && is_user_focused "$term_app"; then
    log "notify($kind) target=$target_window SUPPRESSED (focused)"
    return 0
  fi

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

  log "notify($kind) target=$target_window FIRING terminal-notifier (sound=${sound:-none})"
  terminal-notifier "${args[@]}" >/dev/null 2>&1 || true
  log "notify($kind) target=$target_window FIRED exit=$?"
}

set_waiting() {
  # Fire the banner only on state CHANGE — Claude Code emits both
  # Notification(permission_prompt) and PermissionRequest for the same
  # event, which would otherwise produce a double banner before group
  # dedup catches up.
  local was
  was="$(tmux show-options -wqv -t "$target_window" @claude_waiting 2>/dev/null || true)"
  log "set_waiting target=$target_window prior_waiting='${was}'"
  tmux set-option -wq -t "$target_window" @claude_done ""
  tmux set-option -wq -t "$target_window" @claude_waiting 1
  if [ -z "$was" ]; then
    log "set_waiting target=$target_window calling notify (state CHANGE)"
    notify waiting
  else
    log "set_waiting target=$target_window SKIP notify (already waiting)"
  fi
}

set_done() {
  local was
  was="$(tmux show-options -wqv -t "$target_window" @claude_done 2>/dev/null || true)"
  log "set_done target=$target_window prior_done='${was}'"
  tmux set-option -wq -t "$target_window" @claude_waiting ""
  tmux set-option -wq -t "$target_window" @claude_done 1
  if [ -z "$was" ]; then
    log "set_done target=$target_window calling notify (state CHANGE)"
    notify done
  else
    log "set_done target=$target_window SKIP notify (already done)"
  fi
  # Auto-clear after 10 seconds
  tmux run-shell -b -d 10 \
    "tmux set-option -wq -t '${target_window}' @claude_done ''; \
     tmux set-option -gq @claude_done_msg ''"
}

clear_all() {
  log "clear_all target=$target_window"
  tmux set-option -wq -t "$target_window" @claude_waiting ""
  tmux set-option -wq -t "$target_window" @claude_done ""
  # Also dismiss any standing macOS banner — without this, typing in the
  # tmux session clears the tmux pill but leaves the banner in place.
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -remove "claude-${target_window}" >/dev/null 2>&1 || true
  fi
}

log "ENTER event='$event' target=$target_window TMUX_PANE=$TMUX_PANE"

case "$event" in
  Notification)
    ntype="$(jq -r '.notification_type // empty' <<<"$input")"
    log "  Notification ntype='$ntype'"
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
