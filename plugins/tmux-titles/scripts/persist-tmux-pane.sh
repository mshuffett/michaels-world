#!/bin/bash
set -Eeuo pipefail

# Save TMUX_PANE to Claude's env file so it persists across hooks
if [ -n "${TMUX_PANE:-}" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export TMUX_PANE='$TMUX_PANE'" >> "$CLAUDE_ENV_FILE"
fi
