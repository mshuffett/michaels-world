#!/bin/bash
set -Eeuo pipefail

# Generates a descriptive AI title for the tmux window after enough conversation.
# Runs once per session (flag file prevents re-runs).
# Feeds the model: conversation context, current window name, and other pane context
# so it can produce a smart combined title.

json=$(cat)

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

session_id=$(echo "$json" | jq -r '.session_id // empty')
transcript_path=$(echo "$json" | jq -r '.transcript_path // empty')
cwd=$(echo "$json" | jq -r '.cwd // empty')

if [ -z "$session_id" ] || [ -z "$transcript_path" ]; then
  exit 0
fi

# Expand tilde
transcript_path="${transcript_path/#\~/$HOME}"

# Only generate once per session
flag_file="/tmp/claude-tmux-titles/generated-$session_id"
if [ -f "$flag_file" ]; then
  exit 0
fi

# Wait for enough conversation (3+ user/assistant messages)
if [ ! -f "$transcript_path" ]; then
  exit 0
fi

msg_count=$(jq -s '[.[] | select(.message.role == "user" or .message.role == "assistant")] | length' "$transcript_path" 2>/dev/null || echo 0)
if [ "$msg_count" -lt 3 ]; then
  exit 0
fi

# Gather context for the AI
# 1. Last few user/assistant messages
context=$(jq -s -r '
  [.[] | select(.message.role == "user" or .message.role == "assistant")
   | {role: .message.role, content: (.message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end)}
   | select((.content | length) > 0)]
  | .[-5:]
  | map("\(.role): \(.content)")
  | join("\n")' "$transcript_path" 2>/dev/null || echo "")

if [ -z "$context" ]; then
  exit 0
fi

# 2. Current window name
target=$(tmux display-message -p -t "$TMUX_PANE" "#{session_id}:#{window_id}" 2>/dev/null || echo "")
current_window_name=$(tmux display-message -p -t "$target" "#{window_name}" 2>/dev/null || echo "")

# 3. Other panes in this window (command + directory)
other_panes=""
pane_ids=$(tmux list-panes -t "$target" -F '#{pane_id}' 2>/dev/null || echo "")
for pane_id in $pane_ids; do
  if [ "$pane_id" != "$TMUX_PANE" ]; then
    pane_cmd=$(tmux display-message -p -t "$pane_id" "#{pane_current_command}" 2>/dev/null || echo "")
    pane_path=$(tmux display-message -p -t "$pane_id" "#{pane_current_path}" 2>/dev/null || echo "")
    pane_dir=$(basename "$pane_path" 2>/dev/null || echo "")
    other_panes="${other_panes}Pane running '${pane_cmd}' in ${pane_dir}\n"
  fi
done

# 4. Build the prompt
prompt="Generate a concise 3-5 word title for a tmux window.

Current window name: ${current_window_name}
Project directory: $(basename "$cwd" 2>/dev/null || echo "unknown")"

if [ -n "$other_panes" ]; then
  prompt="${prompt}
Other panes in this window:
$(echo -e "$other_panes")"
fi

prompt="${prompt}

Recent conversation:
${context:0:2000}

Rules:
- Output ONLY the title, nothing else
- 3-5 words max
- Capture the main task/topic
- If other panes are present, incorporate their context naturally
- No quotes, no punctuation, no explanation"

# Generate title using Claude CLI with Haiku
title=$(echo "$prompt" | claude --print --model claude-haiku-4-5-20251001 2>/dev/null | tr '\n' ' ' | head -c 50 | xargs)

if [ -z "$title" ] || [ "$title" = "null" ]; then
  exit 0
fi

# Save the descriptive name for this pane
state_dir="/tmp/claude-tmux-titles"
mkdir -p "$state_dir"
state_file="$state_dir/$(echo "$TMUX_PANE" | tr '%' '_')"
echo "$title" > "$state_file.name"

# Mark as generated
touch "$flag_file"

# Trigger a status update to refresh window with new name
# Read current status or default to working
if [ -f "$state_file.status" ]; then
  current_icon=$(awk '{print $2}' "$state_file.status")
else
  current_icon="✻"
fi

# Update pane title
tmux select-pane -t "$TMUX_PANE" -T "$current_icon $title"

# Update window (bubble-up will use new name)
tmux rename-window -t "$target" "$current_icon $title"
