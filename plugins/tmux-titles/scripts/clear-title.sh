#!/bin/bash
set -Eeuo pipefail

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

# Kill the spinner process
state_dir="/tmp/claude-tmux-titles"
state_file="$state_dir/$(echo "$TMUX_PANE" | tr '%' '_')"

if [ -f "$state_file.spinner-pid" ]; then
  pid=$(cat "$state_file.spinner-pid" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
fi

# Clean up all state files for this pane
rm -f "$state_file.status" "$state_file.name" "$state_file.original-name" "$state_file.spinner-pid" "$state_file.spinner-mode" "$state_file.spinner-icon"

# Re-enable application title setting and reset pane title
tmux set-option -p -t "$TMUX_PANE" allow-rename on 2>/dev/null || true
tmux select-pane -t "$TMUX_PANE" -T "" 2>/dev/null || true

# If no other Claude panes remain, re-enable automatic-rename
target=$(tmux display-message -p -t "$TMUX_PANE" "#{session_id}:#{window_id}" 2>/dev/null || echo "")
if [ -z "$target" ]; then
  exit 0
fi

has_other_claude=false
pane_ids=$(tmux list-panes -t "$target" -F '#{pane_id}' 2>/dev/null || echo "")
for pane_id in $pane_ids; do
  if [ "$pane_id" != "$TMUX_PANE" ]; then
    other_state="$state_dir/$(echo "$pane_id" | tr '%' '_').status"
    if [ -f "$other_state" ]; then
      has_other_claude=true
      break
    fi
  fi
done

if [ "$has_other_claude" = false ]; then
  # Clean up window owner file and re-enable automatic-rename
  window_key=$(echo "$target" | tr ':' '_')
  rm -f "$state_dir/window-${window_key}.owner"
  tmux set-window-option -t "$target" automatic-rename on 2>/dev/null || true
fi
