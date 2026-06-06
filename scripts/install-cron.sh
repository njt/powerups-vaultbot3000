#!/usr/bin/env bash
# Install or update the weekly cron jobs:
#   - Sunday 3am: journal-catchup.sh (backfill missed sessions from the past 7 days)
#   - Sunday 5am: weekly digest via reflect skill
# Safe to run multiple times — replaces any existing vaultbot cron entries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN=$(which claude 2>/dev/null || echo "$HOME/.claude/local/claude")

CATCHUP_CMD="0 3 * * 0 $SCRIPT_DIR/journal-catchup.sh >> /tmp/journal-catchup.log 2>&1"
VAULT="\${OBSIDIAN_VAULT:-\$HOME/obsidian}"
DIGEST_CMD="0 5 * * 0 AGENT_JOURNAL_SESSION=1 $CLAUDE_BIN --print --dangerously-skip-permissions --add-dir ~/.claude/projects --add-dir \"$VAULT\" -p \"Use the /reflect skill with 'weekly' argument to generate this week's digest\" >> /tmp/weekly-digest.log 2>&1"

# Remove any existing vaultbot entries, then add both
(crontab -l 2>/dev/null | grep -v 'journal-catchup' | grep -v '/reflect.*weekly' ; echo "$CATCHUP_CMD"; echo "$DIGEST_CMD") | crontab -

echo "Installed weekly cron jobs:"
echo "  Sunday 3am: journal catch-up"
echo "  Sunday 5am: weekly digest"
