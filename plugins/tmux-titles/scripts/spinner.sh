#!/bin/bash
set -Euo pipefail

# Background spinner that animates the pane title while Claude is working.
# Controlled via state files:
#   .spinner-pid  — PID of this process (for cleanup)
#   .spinner-mode — "spin" (active) or "static" (idle, show fixed icon)
#   .spinner-icon — static icon to show when mode=static
#   .name         — descriptive name to show after the spinner

TMUX_PANE="$1"
STATE_DIR="/tmp/claude-tmux-titles"
STATE_FILE="$STATE_DIR/$(echo "$TMUX_PANE" | tr '%' '_')"

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

while true; do
  mode="spin"
  if [ -f "$STATE_FILE.spinner-mode" ]; then
    mode=$(cat "$STATE_FILE.spinner-mode" 2>/dev/null || echo "spin")
  fi

  # Read the descriptive name
  name=""
  if [ -f "$STATE_FILE.name" ]; then
    name=$(cat "$STATE_FILE.name" 2>/dev/null || echo "")
  fi

  if [ "$mode" = "static" ]; then
    icon="✓"
    if [ -f "$STATE_FILE.spinner-icon" ]; then
      icon=$(cat "$STATE_FILE.spinner-icon" 2>/dev/null || echo "✓")
    fi
    if [ -n "$name" ]; then
      tmux select-pane -t "$TMUX_PANE" -T "$icon $name" 2>/dev/null || true
    else
      tmux select-pane -t "$TMUX_PANE" -T "$icon" 2>/dev/null || true
    fi
    # Sleep longer when static — no need to burn cycles
    sleep 2
  else
    spinner="${FRAMES[$frame_idx]}"
    if [ -n "$name" ]; then
      tmux select-pane -t "$TMUX_PANE" -T "$spinner $name" 2>/dev/null || true
    else
      tmux select-pane -t "$TMUX_PANE" -T "$spinner" 2>/dev/null || true
    fi
    frame_idx=$(( (frame_idx + 1) % FRAME_COUNT ))
    sleep 0.1
  fi
done
