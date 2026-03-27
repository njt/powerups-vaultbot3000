#!/usr/bin/env bash
# Session-end hook: launches a new Claude session to write a journal entry.
# Skips if this is already a journal-writing session (recursion guard).

set -euo pipefail

DEBUG_LOG="/tmp/journal-hook-debug.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') === SessionEnd hook fired ===" >> "$DEBUG_LOG"
echo "  PID=$$  PPID=$PPID" >> "$DEBUG_LOG"
echo "  AGENT_JOURNAL_SESSION=${AGENT_JOURNAL_SESSION:-unset}" >> "$DEBUG_LOG"

# Recursion guard
if [ "${AGENT_JOURNAL_SESSION:-}" = "1" ]; then
  echo "  Skipping: recursion guard" >> "$DEBUG_LOG"
  exit 0
fi

# Find the most recently modified session JSONL across all projects
# Avoid ls|head pipe — pipefail + SIGPIPE kills the script on bash 3.2
LATEST_JSONL=$(ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1 || true)

echo "  LATEST_JSONL=$LATEST_JSONL" >> "$DEBUG_LOG"

if [ -z "$LATEST_JSONL" ]; then
  echo "  Skipping: no JSONL found" >> "$DEBUG_LOG"
  echo '{"continue": true}'
  exit 0
fi

# Extract session ID for logging
SESSION_ID=$(head -1 "$LATEST_JSONL" | jq -r '.sessionId // "unknown"' 2>/dev/null || echo "unknown")
echo "  SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
echo "  claude path: $(which claude 2>/dev/null || echo 'NOT FOUND')" >> "$DEBUG_LOG"

# Launch journal-writing session in background
# The AGENT_JOURNAL_SESSION env var prevents recursion
AGENT_JOURNAL_SESSION=1 nohup claude --print --dangerously-skip-permissions --add-dir "$HOME" -p "Use the /journal skill to write a journal entry for session at: $LATEST_JSONL" \
  > /tmp/agent-journal-last.log 2>&1 &
CHILD_PID=$!
disown

echo "  Launched claude PID=$CHILD_PID" >> "$DEBUG_LOG"

echo '{"continue": true}'
exit 0
