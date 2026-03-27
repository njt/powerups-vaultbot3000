#!/usr/bin/env bash
# Extract a readable conversation summary from a Claude Code session JSONL file.
# Usage: extract-transcript.sh <session-jsonl-path>
#
# Outputs: alternating "## User" and "## Assistant" sections with text content.
# Strips thinking blocks, tool use details, and system messages.
# Includes tool names (but not inputs/outputs) so you know what happened.

set -euo pipefail

JSONL_FILE="${1:?Usage: extract-transcript.sh <path-to-session.jsonl>}"

if [ ! -f "$JSONL_FILE" ]; then
  echo "Error: File not found: $JSONL_FILE" >&2
  exit 1
fi

jq -r '
  select(.type == "user" or .type == "assistant") |
  if .type == "user" then
    "\n## User\n" + (
      .message.content // [] |
      if type == "string" then .
      elif type == "array" then
        map(
          if .type == "text" then .text
          elif .type == "tool_result" then "(tool result: " + (.tool_use_id // "unknown") + ")"
          else empty
          end
        ) | join("\n")
      else ""
      end
    )
  elif .type == "assistant" then
    "\n## Assistant\n" + (
      .message.content // [] |
      map(
        if .type == "text" then .text
        elif .type == "tool_use" then "[tool: " + .name + "]"
        else empty
        end
      ) | join("\n")
    )
  else empty
  end
' "$JSONL_FILE"
