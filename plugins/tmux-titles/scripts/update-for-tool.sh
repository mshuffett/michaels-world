#!/bin/bash
set -Eeuo pipefail

# Maps tool names to status icons, then delegates to update-status.sh

json=$(cat)

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

script_dir="$(command cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool_name=$(echo "$json" | jq --raw-output '.tool_name')

case "$tool_name" in
  Bash)           icon='▶' ;;
  Create|Edit|Write|MultiEdit) icon='✎' ;;
  Read)           icon='…' ;;
  AskUserQuestion) icon='?' ;;
  *)              icon='✻' ;;
esac

echo "$json" | "$script_dir/update-status.sh" "$icon"
