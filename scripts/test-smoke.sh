#!/usr/bin/env bash
# Smoke tests for journal-hook.sh and journal-catchup.sh logic.
# Tests extract logic snippets and run them in isolation — no Claude processes
# are launched. Uses a temp directory tree that mimics the real environment.

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}  FAIL: $1\n"
  echo "  FAIL: $1"
}

# --- Setup ---

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

MOCK_PROJECTS="$TMPDIR_ROOT/projects"
MOCK_VAULT="$TMPDIR_ROOT/vault"
MOCK_SESSIONS="$MOCK_VAULT/Agent Journals/Sessions"
mkdir -p "$MOCK_PROJECTS/testproj" "$MOCK_SESSIONS"

# Helper: create a mock JSONL file with given session ID and entrypoint
make_mock_jsonl() {
  local dir="$1" session_id="$2" entrypoint="$3"
  local jsonl="$dir/${session_id}.jsonl"
  echo "{\"type\":\"attachment\",\"sessionId\":\"${session_id}\",\"entrypoint\":\"${entrypoint}\",\"cwd\":\"/tmp\"}" > "$jsonl"
  # Add enough lines to be non-trivial (>50 for catch-up line count check)
  for i in $(seq 1 55); do
    echo "{\"type\":\"user\",\"message\":{\"content\":\"test message $i\"}}" >> "$jsonl"
  done
  echo "$jsonl"
}

echo "=== Hook Tests ==="

# --- Hook test 1: Recursion guard ---
(
  AGENT_JOURNAL_SESSION=1
  if [ "${AGENT_JOURNAL_SESSION:-}" = "1" ]; then
    exit 0  # Would skip
  fi
  exit 1  # Should not reach here
) && pass "Recursion guard: AGENT_JOURNAL_SESSION=1 causes skip" \
  || fail "Recursion guard: AGENT_JOURNAL_SESSION=1 did not cause skip"

# --- Hook test 1b: No recursion guard when unset ---
(
  unset AGENT_JOURNAL_SESSION
  if [ "${AGENT_JOURNAL_SESSION:-}" = "1" ]; then
    exit 1  # Should not skip
  fi
  exit 0  # Correct: proceeds
) && pass "Recursion guard: unset AGENT_JOURNAL_SESSION proceeds" \
  || fail "Recursion guard: unset AGENT_JOURNAL_SESSION incorrectly skipped"

# --- Hook test 2: Entrypoint filtering — sdk-cli is skipped ---
(
  JSONL=$(make_mock_jsonl "$MOCK_PROJECTS/testproj" "sess-sdkcli-001" "sdk-cli")
  ENTRYPOINT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'attachment':
            print(d.get('entrypoint', 'unknown'))
            break
" "$JSONL" 2>/dev/null || echo "unknown")
  if [ "$ENTRYPOINT" != "cli" ] && [ "$ENTRYPOINT" != "claude-desktop" ]; then
    exit 0  # Correctly skipped
  fi
  exit 1
) && pass "Entrypoint filter: sdk-cli is skipped" \
  || fail "Entrypoint filter: sdk-cli was not skipped"

# --- Hook test 3: Entrypoint filtering — cli proceeds ---
(
  JSONL=$(make_mock_jsonl "$MOCK_PROJECTS/testproj" "sess-cli-002" "cli")
  ENTRYPOINT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'attachment':
            print(d.get('entrypoint', 'unknown'))
            break
" "$JSONL" 2>/dev/null || echo "unknown")
  if [ "$ENTRYPOINT" = "cli" ] || [ "$ENTRYPOINT" = "claude-desktop" ]; then
    exit 0  # Correctly proceeds
  fi
  exit 1
) && pass "Entrypoint filter: cli proceeds" \
  || fail "Entrypoint filter: cli was incorrectly skipped"

# --- Hook test 4: Session ID extraction ---
(
  JSONL=$(make_mock_jsonl "$MOCK_PROJECTS/testproj" "abc12345-6789-0def-ghij-klmnopqrstuv" "cli")
  SESSION_ID=$(head -1 "$JSONL" | jq -r '.sessionId // "unknown"' 2>/dev/null || echo "unknown")
  if [ "$SESSION_ID" = "abc12345-6789-0def-ghij-klmnopqrstuv" ]; then
    exit 0
  fi
  exit 1
) && pass "Session ID extraction: correct ID extracted" \
  || fail "Session ID extraction: wrong ID extracted"

# --- Hook test 5: SESSION_ID=unknown guard ---
(
  # Create a JSONL with no sessionId field
  BAD_JSONL="$MOCK_PROJECTS/testproj/nosession.jsonl"
  echo '{"type":"attachment","entrypoint":"cli","cwd":"/tmp"}' > "$BAD_JSONL"
  SESSION_ID=$(head -1 "$BAD_JSONL" | jq -r '.sessionId // "unknown"' 2>/dev/null || echo "unknown")
  if [ "$SESSION_ID" = "unknown" ]; then
    exit 0  # Correctly detected as unknown — hook would skip
  fi
  exit 1
) && pass "SESSION_ID=unknown guard: missing sessionId detected" \
  || fail "SESSION_ID=unknown guard: missing sessionId not detected"

# --- Hook test 6: Session-ID-based discovery ---
(
  TARGET_ID="deadbeef-1234-5678-abcd-ef0123456789"
  JSONL=$(make_mock_jsonl "$MOCK_PROJECTS/testproj" "$TARGET_ID" "cli")

  # Also create a decoy JSONL to make sure we find the right one
  make_mock_jsonl "$MOCK_PROJECTS/testproj" "othersid-aaaa-bbbb-cccc-dddddddddddd" "cli" > /dev/null

  # Simulate CLAUDE_CODE_SESSION_ID-based discovery
  CLAUDE_CODE_SESSION_ID="$TARGET_ID"
  FOUND=$(find "$MOCK_PROJECTS" -maxdepth 2 -name "${CLAUDE_CODE_SESSION_ID}.jsonl" -type f 2>/dev/null | head -1 || true)
  if [ "$FOUND" = "$JSONL" ]; then
    exit 0
  fi
  echo "Expected: $JSONL" >&2
  echo "Got: $FOUND" >&2
  exit 1
) && pass "Session-ID-based discovery: finds correct JSONL" \
  || fail "Session-ID-based discovery: did not find correct JSONL"

echo ""
echo "=== Catch-up Tests ==="

# --- Catch-up test 1: Empty vault — JOURNALED is empty ---
(
  EMPTY_SESSIONS="$TMPDIR_ROOT/empty-sessions"
  mkdir -p "$EMPTY_SESSIONS"
  JOURNALED=$(find "$EMPTY_SESSIONS" -maxdepth 1 -name "*.md" -print0 2>/dev/null | xargs -0 grep -h "^session:" /dev/null 2>/dev/null | sed 's/session: //' | sort -u || true)
  if [ -z "$JOURNALED" ]; then
    JOURNAL_COUNT=0
  else
    JOURNAL_COUNT=$(echo "$JOURNALED" | wc -l | tr -d ' ')
  fi
  if [ "$JOURNAL_COUNT" -eq 0 ]; then
    exit 0
  fi
  exit 1
) && pass "Empty vault: JOURNAL_COUNT is 0" \
  || fail "Empty vault: JOURNAL_COUNT was not 0"

# --- Catch-up test 2: Existing journals — collects session IDs ---
(
  POP_SESSIONS="$TMPDIR_ROOT/pop-sessions"
  mkdir -p "$POP_SESSIONS"
  # Create mock journal files with session frontmatter
  cat > "$POP_SESSIONS/journal1.md" << 'MDEOF'
---
session: aaaaaaaa-1111-2222-3333-444444444444
date: 2026-06-01
---
# Journal 1
MDEOF
  cat > "$POP_SESSIONS/journal2.md" << 'MDEOF'
---
session: bbbbbbbb-5555-6666-7777-888888888888
date: 2026-06-02
---
# Journal 2
MDEOF

  JOURNALED=$(find "$POP_SESSIONS" -maxdepth 1 -name "*.md" -print0 2>/dev/null | xargs -0 grep -h "^session:" /dev/null 2>/dev/null | sed 's/session: //' | sort -u || true)
  if [ -z "$JOURNALED" ]; then
    JOURNAL_COUNT=0
  else
    JOURNAL_COUNT=$(echo "$JOURNALED" | wc -l | tr -d ' ')
  fi
  if [ "$JOURNAL_COUNT" -eq 2 ]; then
    # Verify specific IDs are present
    if echo "$JOURNALED" | grep -q "aaaaaaaa-1111-2222-3333-444444444444" && \
       echo "$JOURNALED" | grep -q "bbbbbbbb-5555-6666-7777-888888888888"; then
      exit 0
    fi
  fi
  echo "JOURNAL_COUNT=$JOURNAL_COUNT, JOURNALED=$JOURNALED" >&2
  exit 1
) && pass "Existing journals: collects 2 session IDs" \
  || fail "Existing journals: did not collect correct session IDs"

# --- Catch-up test 3: Dedup (full ID) ---
(
  FULL_ID="cccccccc-9999-aaaa-bbbb-dddddddddddd"
  JOURNALED="$FULL_ID"
  fname="$FULL_ID"
  prefix="${fname:0:8}"

  # Full ID match OR legacy prefix match
  if echo "$JOURNALED" | grep -E -q "^${fname}$|^${prefix}$" 2>/dev/null; then
    exit 0  # Correctly deduped
  fi
  exit 1
) && pass "Dedup (full ID): already-journaled session is skipped" \
  || fail "Dedup (full ID): already-journaled session was not skipped"

# --- Catch-up test 4: Dedup (legacy prefix) ---
(
  # JOURNALED has only the 8-char prefix (legacy format)
  JOURNALED="dddddddd"
  fname="dddddddd-1111-2222-3333-eeeeeeeeeeee"
  prefix="${fname:0:8}"

  if echo "$JOURNALED" | grep -E -q "^${fname}$|^${prefix}$" 2>/dev/null; then
    exit 0  # Correctly deduped via prefix
  fi
  exit 1
) && pass "Dedup (legacy prefix): 8-char prefix match causes skip" \
  || fail "Dedup (legacy prefix): 8-char prefix match did not cause skip"

# --- Catch-up test 5: Lock prevents duplicate ---
(
  LOCK_PREFIX="eeeeeeee"
  LOCK_DIR="/tmp/journal-lock-${LOCK_PREFIX}"
  # Ensure clean state
  rmdir "$LOCK_DIR" 2>/dev/null || true

  # First claim should succeed
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    rm -rf "$LOCK_DIR"
    exit 1
  fi

  # Second claim should fail (already locked)
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    rm -rf "$LOCK_DIR"
    exit 1  # Should have failed
  fi

  rm -rf "$LOCK_DIR"
  exit 0
) && pass "Lock prevents duplicate: second mkdir fails" \
  || fail "Lock prevents duplicate: second mkdir did not fail"

# --- Catch-up test 6: Agent-* files skipped ---
(
  fname="agent-subagent-task-12345678"
  if [[ "$fname" == agent-* ]]; then
    exit 0  # Correctly skipped
  fi
  exit 1
) && pass "Agent-* files: agent- prefix is skipped" \
  || fail "Agent-* files: agent- prefix was not skipped"

# --- Catch-up test 6b: Non-agent files proceed ---
(
  fname="12345678-abcd-efgh-ijkl-mnopqrstuvwx"
  if [[ "$fname" == agent-* ]]; then
    exit 1  # Should not skip
  fi
  exit 0
) && pass "Agent-* files: normal filename proceeds" \
  || fail "Agent-* files: normal filename was incorrectly skipped"

# --- Summary ---
echo ""
echo "=== Results ==="
TOTAL=$((PASS + FAIL))
echo "  $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
fi
echo "  All tests passed."
exit 0
