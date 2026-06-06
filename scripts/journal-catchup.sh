#!/usr/bin/env bash
# Weekly catch-up: find unjournaled interactive sessions from the past 7 days
# and journal them. Intended to run via cron to catch sessions missed by the
# session-end hook (reboots, crashes, hook failures).
# Skips subagent/--print sessions (entrypoint != cli/claude-desktop).

set -euo pipefail

LOG="/tmp/journal-catchup.log"
VAULT="${OBSIDIAN_VAULT:-$HOME/obsidian}"
SESSIONS_DIR="$VAULT/Agent Journals/Sessions"
mkdir -p "$SESSIONS_DIR"
PROJECTS_DIR="$HOME/.claude/projects"
MAX_CONCURRENT=3

echo "$(date '+%Y-%m-%d %H:%M:%S') === Journal catch-up started ===" >> "$LOG"

# 1. Collect session IDs already journaled
JOURNALED=$(find "$SESSIONS_DIR" -maxdepth 1 -name "*.md" -print0 2>/dev/null | xargs -0 grep -h "^session:" 2>/dev/null | sed 's/session: //' | sort -u || true)
if [ -z "$JOURNALED" ]; then
  JOURNAL_COUNT=0
else
  JOURNAL_COUNT=$(echo "$JOURNALED" | wc -l | tr -d ' ')
fi
echo "  Found $JOURNAL_COUNT existing journals" >> "$LOG"

# 2. Find JSONL files from the past 7 days, skip non-interactive/already-journaled
QUEUE=()
while IFS= read -r jsonl; do
  [ -z "$jsonl" ] && continue
  fname=$(basename "$jsonl" .jsonl)

  # Skip subagent files (in subagents/ subdirectories)
  [[ "$fname" == agent-* ]] && continue

  # Skip trivial sessions (<50 lines)
  lines=$(wc -l < "$jsonl" 2>/dev/null | tr -d ' ')
  [ "$lines" -lt 50 ] && continue

  # Skip non-interactive sessions (subagents, --print invocations)
  entrypoint=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'attachment':
            print(d.get('entrypoint', 'unknown'))
            break
" "$jsonl" 2>/dev/null || echo "unknown")
  if [ "$entrypoint" != "cli" ] && [ "$entrypoint" != "claude-desktop" ]; then
    continue
  fi

  # Atomically claim this session — skip if hook or another catch-up already has it
  prefix="${fname:0:8}"
  LOCK_DIR="/tmp/journal-lock-${prefix}"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    continue
  fi

  # Skip already-journaled sessions (match full session ID)
  if echo "$JOURNALED" | grep -q "^${fname}$" 2>/dev/null; then
    continue
  fi

  QUEUE+=("$jsonl")
done < <(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -mtime -7 2>/dev/null)

echo "  Found ${#QUEUE[@]} unjournaled interactive sessions to process" >> "$LOG"

if [ ${#QUEUE[@]} -eq 0 ]; then
  echo "  Nothing to do" >> "$LOG"
  exit 0
fi

# 3. Process each unjournaled session, throttling concurrency
# Scope --add-dir to just what's needed: transcripts and vault
# PID tracking for bash 3.2 compat (wait -n requires bash 4.3+)
PIDS=()
for jsonl in "${QUEUE[@]}"; do
  sid=$(basename "$jsonl" .jsonl)
  prefix="${sid:0:8}"
  echo "  Journaling: $prefix" >> "$LOG"

  AGENT_JOURNAL_SESSION=1 nohup claude --print --dangerously-skip-permissions \
    --add-dir ~/.claude/projects --add-dir "$VAULT" \
    -p "Use the /journal skill to write a journal entry for session at: $jsonl" \
    > "/tmp/journal-catchup-${prefix}.log" 2>&1 &
  PIDS+=($!)

  if [ "${#PIDS[@]}" -ge "$MAX_CONCURRENT" ]; then
    wait "${PIDS[0]}" 2>/dev/null || true
    PIDS=("${PIDS[@]:1}")
  fi
done

for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
echo "$(date '+%Y-%m-%d %H:%M:%S') === Journal catch-up finished (${#QUEUE[@]} sessions) ===" >> "$LOG"
