#!/usr/bin/env bash
# Session-end hook: launches a new Claude session to write a journal entry.
# Only journals interactive CLI sessions — skips subagents, --print sessions,
# and journal-writing sessions (recursion guard).

set -euo pipefail

DEBUG_LOG="/tmp/journal-hook-debug.log"
VAULT="${OBSIDIAN_VAULT:-$HOME/obsidian}"

echo "$(date '+%Y-%m-%d %H:%M:%S') === SessionEnd hook fired ===" >> "$DEBUG_LOG"
echo "  PID=$$  PPID=$PPID" >> "$DEBUG_LOG"
echo "  AGENT_JOURNAL_SESSION=${AGENT_JOURNAL_SESSION:-unset}" >> "$DEBUG_LOG"

# Recursion guard
if [ "${AGENT_JOURNAL_SESSION:-}" = "1" ]; then
  echo "  Skipping: recursion guard" >> "$DEBUG_LOG"
  exit 0
fi

# Find the JSONL for the session that just ended.
# Prefer CLAUDE_CODE_SESSION_ID (set by Claude Code in hook env) — maps directly
# to the JSONL filename, eliminating the race where two simultaneous session-end
# hooks both pick the same "most recent" file.
# Fall back to "most recently modified" heuristic for older Claude Code versions.
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  LATEST_JSONL=$(find ~/.claude/projects -maxdepth 2 -name "${CLAUDE_CODE_SESSION_ID}.jsonl" -type f 2>/dev/null | head -1 || true)
  echo "  CLAUDE_CODE_SESSION_ID=$CLAUDE_CODE_SESSION_ID" >> "$DEBUG_LOG"
  echo "  LATEST_JSONL=$LATEST_JSONL (by session ID)" >> "$DEBUG_LOG"
fi

if [ -z "${LATEST_JSONL:-}" ]; then
  # Fallback: most recently modified JSONL. Has a race if two sessions end
  # simultaneously — both hooks pick the same file. Catch-up covers the gap.
  # Use find instead of ls glob — glob fails with "argument list too long" at ~14k files
  # stat -f is macOS, stat -c is Linux — try both
  LATEST_JSONL=$(find ~/.claude/projects -maxdepth 2 -name "*.jsonl" -type f -print0 2>/dev/null | (xargs -0 stat -f '%m %N' 2>/dev/null || xargs -0 stat -c '%Y %n' 2>/dev/null) | sort -rn | head -1 | cut -d' ' -f2- || true)
  echo "  LATEST_JSONL=$LATEST_JSONL (by mtime fallback)" >> "$DEBUG_LOG"
fi

if [ -z "$LATEST_JSONL" ]; then
  echo "  Skipping: no JSONL found" >> "$DEBUG_LOG"
  echo '{"continue": true}'
  exit 0
fi

# Only journal interactive CLI sessions — skip subagents and --print invocations
ENTRYPOINT=$(python3 -c "
import json
with open('$LATEST_JSONL') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'attachment':
            print(d.get('entrypoint', 'unknown'))
            break
" 2>/dev/null || echo "unknown")

echo "  ENTRYPOINT=$ENTRYPOINT" >> "$DEBUG_LOG"

if [ "$ENTRYPOINT" != "cli" ] && [ "$ENTRYPOINT" != "claude-desktop" ]; then
  echo "  Skipping: non-interactive session (entrypoint=$ENTRYPOINT)" >> "$DEBUG_LOG"
  echo '{"continue": true}'
  exit 0
fi

# Extract session ID for logging
SESSION_ID=$(head -1 "$LATEST_JSONL" | jq -r '.sessionId // "unknown"' 2>/dev/null || echo "unknown")
echo "  SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
echo "  claude path: $(which claude 2>/dev/null || echo 'NOT FOUND')" >> "$DEBUG_LOG"

# Launch journal-writing session in background
# Scope --add-dir to just what's needed: transcripts and vault
AGENT_JOURNAL_SESSION=1 nohup claude --print --dangerously-skip-permissions \
  --add-dir ~/.claude/projects --add-dir "$VAULT" \
  -p "Use the /journal skill to write a journal entry for session at: $LATEST_JSONL" \
  > /tmp/agent-journal-last.log 2>&1 &
CHILD_PID=$!
disown

echo "  Launched claude PID=$CHILD_PID" >> "$DEBUG_LOG"

echo '{"continue": true}'
exit 0
