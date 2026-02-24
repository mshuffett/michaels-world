# tmux-titles

Smart tmux window and pane titles for Claude Code sessions.

## Features

- **Per-pane status icons** in pane borders — each Claude pane shows its own status
- **AI-generated descriptive names** via Claude Haiku — "Refactor Auth Flow" instead of "2.1.51"
- **Multi-pane awareness** — feeds other pane context to the AI for combined titles
- **Priority-based bubble-up** — window name shows the highest-priority Claude status across all panes
- **Suppresses version title** — sets `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`

## Status Icons

| Icon | Meaning | Trigger |
|------|---------|---------|
| `?` | Needs your attention | Permission prompt, question |
| `✻` | Working | Processing, tool use |
| `$` | Running shell command | Bash tool |
| `✎` | Editing files | Edit/Write/MultiEdit |
| `…` | Reading files | Read tool |
| `⌫` | Compacting context | PreCompact |
| `○` | Session started | SessionStart |
| `✓` | Done | Stop |

## Priority Bubble-Up

When multiple Claude panes share a window, the window title shows the highest-priority state:

```
? (needs input) > ✻ (working) > $ (shell) > ✎ (editing) > … (reading) > ⌫ (compact) > ○ (started) > ✓ (done)
```

## AI Title Generation

After 3+ messages, the plugin calls `claude --print --model claude-haiku-4-5-20251001` to generate a descriptive 3-5 word title. It sends:

- Recent conversation context
- Current window name
- Other panes in the window (command + directory)

This runs once per session in the background.

## Requirements

- `jq` for JSON parsing
- `claude` CLI available on PATH (for AI title generation)
- tmux running

## Installation

```bash
claude plugin marketplace add mshuffett/michaels-world
claude plugin install tmux-titles@michaels-world
```

## Recommended tmux config

```tmux
# Show pane titles in borders
set -g pane-border-status top
set -g pane-border-format " #{pane_index} #{pane_title} "
```
