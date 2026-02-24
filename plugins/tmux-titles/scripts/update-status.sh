#!/bin/bash
set -Eeuo pipefail

# Bubbles up Claude status to the window name based on priority.
# Controls the background spinner for pane title animation.
# When Claude is active: spinner animates in pane border.
# When Claude stops: static icon shown.

json=$(cat)
indicator="${1:-}"

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

# Resolve our window
target=$(tmux display-message -p -t "$TMUX_PANE" "#{session_id}:#{window_id}" 2>/dev/null || echo "")
if [ -z "$target" ]; then
  exit 0
fi

# State directory
cwd=$(echo "$json" | jq --raw-output '.cwd // empty' 2>/dev/null || echo "")
state_dir="/tmp/claude-tmux-titles"
mkdir -p "$state_dir"
state_file="$state_dir/$(echo "$TMUX_PANE" | tr '%' '_')"

# Read saved descriptive name for this pane, fall back to original window name
if [ -f "$state_file.name" ]; then
  base_name=$(cat "$state_file.name")
else
  # First run: capture the original window name before we modify it
  if [ ! -f "$state_file.original-name" ]; then
    original=$(tmux display-message -p -t "$target" "#{window_name}" 2>/dev/null || echo "")
    # Discard unhelpful defaults: version numbers, "claude", "Claude Code", shell names
    if echo "$original" | grep -qiE '^[0-9]+\.[0-9]+|^claude|^zsh$|^bash$|^fish$'; then
      original=""
    fi
    # Use original if meaningful, otherwise fall back to 🦞 dirname
    if [ -z "$original" ]; then
      if [ -n "$cwd" ]; then
        original="🦞 $(basename "$cwd")"
      else
        original="🦞"
      fi
    fi
    echo "$original" > "$state_file.original-name"
  fi
  base_name=$(cat "$state_file.original-name")
fi

# Start spinner if not already running
if [ ! -f "$state_file.spinner-pid" ] || ! kill -0 "$(cat "$state_file.spinner-pid" 2>/dev/null)" 2>/dev/null; then
  # Prevent Claude CLI from overriding pane title via escape sequences
  tmux set-option -p -t "$TMUX_PANE" allow-rename off 2>/dev/null || true
  script_dir="$(command cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  nohup "$script_dir/spinner.sh" "$TMUX_PANE" > /dev/null 2>&1 &
  disown
fi

# Set spinner mode based on indicator
# Active states get the animated spinner, terminal states get static icon
case "$indicator" in
  '✓'|'○'|'?')
    echo "static" > "$state_file.spinner-mode"
    echo "$indicator" > "$state_file.spinner-icon"
    ;;
  *)
    echo "spin" > "$state_file.spinner-mode"
    ;;
esac

# Save this pane's priority for bubble-up
# Priority: ? (10) > ✻ (8) > ▶ (7) > ✎ (6) > … (5) > ⌫ (4) > ○ (3) > ✓ (2)
case "$indicator" in
  '?') priority=10 ;;
  '✻') priority=8 ;;
  '▶') priority=7 ;;
  '✎') priority=6 ;;
  '…') priority=5 ;;
  '⌫') priority=4 ;;
  '○') priority=3 ;;
  '✓') priority=2 ;;
  *)   priority=1 ;;
esac
echo "$priority $indicator" > "$state_file.status"

# Bubble up: find highest-priority Claude pane in this window
best_priority=0
best_indicator=""
best_name=""
best_pane=""

pane_ids=$(tmux list-panes -t "$target" -F '#{pane_id}' 2>/dev/null || echo "")

for pane_id in $pane_ids; do
  pane_state="$state_dir/$(echo "$pane_id" | tr '%' '_').status"
  if [ -f "$pane_state" ]; then
    p=$(awk '{print $1}' "$pane_state")
    icon=$(awk '{print $2}' "$pane_state")
    if [ "$p" -gt "$best_priority" ]; then
      best_priority=$p
      best_indicator=$icon
      best_pane=$pane_id
      pane_name_file="$state_dir/$(echo "$pane_id" | tr '%' '_').name"
      pane_orig_file="$state_dir/$(echo "$pane_id" | tr '%' '_').original-name"
      if [ -f "$pane_name_file" ]; then
        best_name=$(cat "$pane_name_file")
      elif [ -f "$pane_orig_file" ]; then
        best_name=$(cat "$pane_orig_file")
      fi
    fi
  fi
done

if [ -z "$best_indicator" ]; then
  best_indicator="$indicator"
fi
if [ -z "$best_name" ]; then
  best_name="$base_name"
fi
if [ -z "$best_pane" ]; then
  best_pane="$TMUX_PANE"
fi

# Record which pane owns the window name (for spinner to use)
window_key=$(echo "$target" | tr ':' '_')
echo "$best_pane" > "$state_dir/window-${window_key}.owner"

# The spinner will handle the animated window name; no static rename needed here
