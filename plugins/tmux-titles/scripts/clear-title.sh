#!/bin/bash
set -Eeuo pipefail

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

# Clean up state files for this pane
state_dir="/tmp/claude-tmux-titles"
state_file="$state_dir/$(echo "$TMUX_PANE" | tr '%' '_')"
rm -f "$state_file.status" "$state_file.name"

# Reset pane title
tmux select-pane -t "$TMUX_PANE" -T "" 2>/dev/null || true

# If other Claude panes remain in this window, let them own the window name.
# Otherwise, re-enable automatic-rename so tmux takes over.
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
  # No other Claude panes — let tmux auto-rename again
  tmux set-window-option -t "$target" automatic-rename on 2>/dev/null || true
fi
