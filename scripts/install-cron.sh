#!/usr/bin/env bash
# Install or update the weekly digest cron job.
# Runs every Sunday at 5am local time.
# Safe to run multiple times — replaces any existing vaultbot cron entry.

set -euo pipefail

CLAUDE_BIN=$(which claude 2>/dev/null || echo "$HOME/.claude/local/claude")
CRON_CMD="0 5 * * 0 AGENT_JOURNAL_SESSION=1 $CLAUDE_BIN --print --dangerously-skip-permissions -p \"Use the /reflect skill with 'weekly' argument to generate this week's digest\" >> /tmp/weekly-digest.log 2>&1"

# Remove any existing vaultbot weekly digest entry, then add the new one
(crontab -l 2>/dev/null | grep -v '/reflect.*weekly' ; echo "$CRON_CMD") | crontab -

echo "Installed weekly digest cron job (Sunday 5am):"
echo "  $CRON_CMD"
