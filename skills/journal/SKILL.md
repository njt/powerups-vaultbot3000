---
name: journal
description: Use when a session ends or when you want to write a journal entry for a Claude Code session into the Obsidian vault
---

# Write Session Journal

Write a journal entry for a Claude Code session into the Obsidian vault.

## Vault Path

Read the vault path from the `OBSIDIAN_VAULT` environment variable. If not set, default to `~/obsidian`. All paths below use `$VAULT` as shorthand for this resolved path.

```bash
VAULT="${OBSIDIAN_VAULT:-$HOME/obsidian}"
```

## Voice

If the user has a custom writing voice skill (e.g. a `nat-write` or similar style skill), use it for all prose. Otherwise, write in a direct, concrete style: no throat-clearing, no AI summary voice ("In this session, we successfully..."), honest about mess, mark open questions with [brackets]. Parenthetical asides for editorial color are fine.

## Input

This skill can be invoked two ways:

1. **Automatically via session-end hook** — the hook passes a session JSONL path as an argument
2. **Manually** — user types /journal and optionally provides a session ID or path

If no session is specified, journal the current session (read its own JSONL).

## Process

1. **Find the session transcript.** If a path was provided, use it. Otherwise, find the most recent JSONL in ~/.claude/projects/:

   ```bash
   # stat -f is macOS, stat -c is Linux
   find ~/.claude/projects -maxdepth 2 -name "*.jsonl" -type f -print0 | \
     (xargs -0 stat -f '%m %N' 2>/dev/null || xargs -0 stat -c '%Y %n' 2>/dev/null) | \
     sort -rn | head -1 | cut -d' ' -f2-
   ```

2. **Extract readable conversation.** Run this jq pipeline to get a readable transcript:

   ```bash
   jq -r '
     select(.type == "user" or .type == "assistant") |
     if .type == "user" then
       "\n## User\n" + (
         .message.content // [] |
         if type == "string" then .
         elif type == "array" then
           map(
             if .type == "text" then .text
             elif .type == "tool_result" then "(tool result)"
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
   ' <path-to-jsonl>
   ```

   Read the output to understand what happened in the session.

3. **Redact secrets.** Before writing anything, scan the transcript for API keys, passwords, tokens, credentials, connection strings, or other secrets. Never include these in the journal entry. If a secret is relevant to the narrative (e.g. "configured the API key"), mention the action without reproducing the value.

4. **De minimis check.** If the session has no substance worth recording — a test ping, a single trivial question, an accidental start with no real work — skip writing a journal. Just output "Skipping: session too trivial to journal" and stop. Use your judgment; a short session with a meaningful decision or insight is still worth capturing.

5. **Get session metadata.** Extract the session ID, project path, and start time from the JSONL:

   ```bash
   head -1 <path-to-jsonl> | jq '{sessionId, cwd, timestamp}'
   ```

6. **Check for existing journals today.** List files matching today's date in Sessions/ to determine the letter suffix:

   ```bash
   ls "$VAULT"/"Agent Journals"/Sessions/$(date +%Y-%m-%d)* 2>/dev/null
   ```

   If no files: no suffix. If files exist: use next letter (a, b, c...).

7. **Write the journal.** The content must follow this exact format:

   **Frontmatter:**
   ```yaml
   ---
   session: <full session ID>
   date: YYYY-MM-DD
   project: <working directory path>
   threads:
     - <inferred thread name(s) — what was the user trying to accomplish?>
   tools_installed:
     - <any software installed or configured, if applicable>
   tags:
     - <topic tags>
   ---
   ```

   **Body sections:**
   ```
   # YYYY-MM-DD — <descriptive title>

   ## Summary
   One to three sentences. What happened and why it matters.

   ## What Happened
   Narrative of the session. Key decisions, approaches tried, pivots.

   ## What Worked
   - Things that went well (uneven bullet lengths are fine)

   ## What Didn't
   - Friction, failures, dead ends
   - Use [bracket notes] for unresolved questions

   ## Learnings
   - Durable takeaways

   ## Improvement Ideas
   - Concrete suggestions for skills, commands, workflow changes
   - Only include if there are genuine ideas (skip section if empty)
   ```

8. **Write the file** to `$VAULT/Agent Journals/Sessions/<filename>`. Create parent directories if needed. If `notesmd` is available, use `notesmd create "Agent Journals/Sessions/<filename>" --content "<content>"`. Otherwise, write the file directly.

   Filename follows: `YYYY-MM-DD - Title.md` (with optional letter suffix like `a`, `b`, `c` for multiple sessions per day).

## Thread Naming

When proposing thread names in the threads frontmatter field:

- Name the thread after the **intent**, not the directory. "Meeting Transcription Pipeline" not "/Users/someone/Source"
- Check existing thread files in `$VAULT/Agent Journals/Threads/` and reuse names when the work is a continuation
- A session can belong to multiple threads
- Short sessions (quick questions, config changes) can have a generic thread like "Misc" or a specific one — use judgment

## Recursion Guard

The session-end hook already prevents recursive journaling (the hook script checks AGENT_JOURNAL_SESSION and exits early). This skill should always run when invoked — do not skip based on environment variables.
