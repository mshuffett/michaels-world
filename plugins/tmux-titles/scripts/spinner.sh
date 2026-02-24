#!/bin/bash
set -Euo pipefail

# Background spinner that animates both pane title and window name while Claude is working.
# Controlled via state files:
#   .spinner-pid  — PID of this process (for cleanup)
#   .spinner-mode — "spin" (active) or "static" (idle, show fixed icon)
#   .spinner-icon — static icon to show when mode=static
#   .name         — descriptive name to show after the spinner
#   .original-name — original window name captured before plugin modified it
# Window ownership:
#   window-{key}.owner — pane ID that should control the window name

TMUX_PANE="$1"
STATE_DIR="/tmp/claude-tmux-titles"
STATE_FILE="$STATE_DIR/$(echo "$TMUX_PANE" | tr '%' '_')"

# Resolve window target once at startup
WINDOW_TARGET=$(tmux display-message -p -t "$TMUX_PANE" "#{session_id}:#{window_id}" 2>/dev/null || echo "")
WINDOW_KEY=$(echo "$WINDOW_TARGET" | tr ':' '_')

# Braille spinner frames
FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
FRAME_COUNT=${#FRAMES[@]}
frame_idx=0

cleanup() {
  rm -f "$STATE_FILE.spinner-pid"
  exit 0
}
trap cleanup EXIT TERM INT

echo $$ > "$STATE_FILE.spinner-pid"

check_counter=0

while true; do
  # Every ~50 iterations (~5s when spinning), verify pane still exists
  check_counter=$(( (check_counter + 1) % 50 ))
  if [ "$check_counter" -eq 0 ]; then
    if ! tmux display-message -p -t "$TMUX_PANE" "#{pane_id}" > /dev/null 2>&1; then
      cleanup
    fi
  fi
  mode="spin"
  if [ -f "$STATE_FILE.spinner-mode" ]; then
    mode=$(cat "$STATE_FILE.spinner-mode" 2>/dev/null || echo "spin")
  fi

  # Read the descriptive name, fall back to original window name
  name=""
  if [ -f "$STATE_FILE.name" ]; then
    name=$(cat "$STATE_FILE.name" 2>/dev/null || echo "")
  elif [ -f "$STATE_FILE.original-name" ]; then
    name=$(cat "$STATE_FILE.original-name" 2>/dev/null || echo "")
  fi

  # Check if this pane owns the window name
  owns_window=false
  owner_file="$STATE_DIR/window-${WINDOW_KEY}.owner"
  if [ -f "$owner_file" ]; then
    if [ "$(cat "$owner_file" 2>/dev/null)" = "$TMUX_PANE" ]; then
      owns_window=true
    fi
  else
    # No owner file yet — assume we own it (single pane case)
    owns_window=true
  fi

  if [ "$mode" = "static" ]; then
    icon="✓"
    if [ -f "$STATE_FILE.spinner-icon" ]; then
      icon=$(cat "$STATE_FILE.spinner-icon" 2>/dev/null || echo "✓")
    fi
    if [ -n "$name" ]; then
      tmux select-pane -t "$TMUX_PANE" -T "$icon $name" 2>/dev/null || true
      if [ "$owns_window" = true ] && [ -n "$WINDOW_TARGET" ]; then
        tmux rename-window -t "$WINDOW_TARGET" "$icon $name" 2>/dev/null || true
      fi
    else
      tmux select-pane -t "$TMUX_PANE" -T "$icon" 2>/dev/null || true
      if [ "$owns_window" = true ] && [ -n "$WINDOW_TARGET" ]; then
        tmux rename-window -t "$WINDOW_TARGET" "$icon" 2>/dev/null || true
      fi
    fi
    # Sleep longer when static — no need to burn cycles
    sleep 2
  else
    spinner="${FRAMES[$frame_idx]}"
    if [ -n "$name" ]; then
      tmux select-pane -t "$TMUX_PANE" -T "$spinner $name" 2>/dev/null || true
      if [ "$owns_window" = true ] && [ -n "$WINDOW_TARGET" ]; then
        tmux rename-window -t "$WINDOW_TARGET" "$spinner $name" 2>/dev/null || true
      fi
    else
      tmux select-pane -t "$TMUX_PANE" -T "$spinner" 2>/dev/null || true
      if [ "$owns_window" = true ] && [ -n "$WINDOW_TARGET" ]; then
        tmux rename-window -t "$WINDOW_TARGET" "$spinner" 2>/dev/null || true
      fi
    fi
    frame_idx=$(( (frame_idx + 1) % FRAME_COUNT ))
    sleep 0.1
  fi
done
