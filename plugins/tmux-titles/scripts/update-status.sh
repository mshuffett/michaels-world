#!/bin/bash
set -Eeuo pipefail

# Updates pane title and bubbles up to window name based on priority.
#
# Always sets the pane title for this Claude pane.
# For the window name: finds the highest-priority Claude status across all
# panes in the window and uses that as the window title.

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

# Get the descriptive name (set by maybe-generate-title.sh) or fall back to directory
cwd=$(echo "$json" | jq --raw-output '.cwd // empty' 2>/dev/null || echo "")
state_dir="/tmp/claude-tmux-titles"
mkdir -p "$state_dir"
state_file="$state_dir/$(echo "$TMUX_PANE" | tr '%' '_')"

# Read saved descriptive name for this pane, fall back to directory basename
if [ -f "$state_file.name" ]; then
  base_name=$(cat "$state_file.name")
elif [ -n "$cwd" ]; then
  base_name=$(basename "$cwd")
else
  base_name="claude"
fi

# 1. Always set per-pane title
tmux select-pane -t "$TMUX_PANE" -T "$indicator $base_name"

# 2. Save this pane's priority for bubble-up
# Priority: ? (10) > ✻ (8) > $ (7) > ✎ (6) > … (5) > ⌫ (4) > ○ (3) > ✓ (2)
case "$indicator" in
  '?') priority=10 ;;
  '✻') priority=8 ;;
  '$') priority=7 ;;
  '✎') priority=6 ;;
  '…') priority=5 ;;
  '⌫') priority=4 ;;
  '○') priority=3 ;;
  '✓') priority=2 ;;
  *)   priority=1 ;;
esac
echo "$priority $indicator" > "$state_file.status"

# 3. Bubble up: find highest-priority Claude pane in this window
best_priority=0
best_indicator=""
best_name=""

# Get all pane IDs in this window
pane_ids=$(tmux list-panes -t "$target" -F '#{pane_id}' 2>/dev/null || echo "")

for pane_id in $pane_ids; do
  pane_state="$state_dir/$(echo "$pane_id" | tr '%' '_').status"
  if [ -f "$pane_state" ]; then
    p=$(awk '{print $1}' "$pane_state")
    icon=$(awk '{print $2}' "$pane_state")
    if [ "$p" -gt "$best_priority" ]; then
      best_priority=$p
      best_indicator=$icon
      # Use that pane's name
      pane_name_file="$state_dir/$(echo "$pane_id" | tr '%' '_').name"
      if [ -f "$pane_name_file" ]; then
        best_name=$(cat "$pane_name_file")
      fi
    fi
  fi
done

# Fall back to current pane's info if nothing better found
if [ -z "$best_indicator" ]; then
  best_indicator="$indicator"
fi
if [ -z "$best_name" ]; then
  best_name="$base_name"
fi

# 4. Set window name to highest-priority pane's status
tmux rename-window -t "$target" "$best_indicator $best_name"
