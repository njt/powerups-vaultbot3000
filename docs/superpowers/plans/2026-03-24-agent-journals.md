# Agent Journals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an automated journaling system for Claude Code sessions that writes structured records into Obsidian, with thread tracking and weekly reflection.

**Architecture:** Three skills (`/journal`, `/reflect`, weekly digest prompt) writing into three Obsidian folders (`Sessions/`, `Threads/`, `Weekly/`) via `notesmd` CLI. A session-end hook triggers `/journal` automatically. A scheduled agent runs the weekly digest.

**Tech Stack:** Claude Code skills (markdown), shell scripts, `notesmd` CLI, `jq`, Claude Code hooks, scheduled agents.

**Spec:** `docs/superpowers/specs/2026-03-24-agent-journals-design.md`

---

### Task 1: Create Vault Folder Structure

**Files:**
- Create: `~/obsidian/Agent Journals/Sessions/.gitkeep` (via notesmd)
- Create: `~/obsidian/Agent Journals/Threads/.gitkeep` (via notesmd)
- Create: `~/obsidian/Agent Journals/Weekly/.gitkeep` (via notesmd)

- [ ] **Step 1: Create the three subfolders**

```bash
mkdir -p ~/obsidian/"Agent Journals"/Sessions
mkdir -p ~/obsidian/"Agent Journals"/Threads
mkdir -p ~/obsidian/"Agent Journals"/Weekly
```

- [ ] **Step 2: Verify folders exist in Obsidian vault**

```bash
ls -la ~/obsidian/"Agent Journals"/
```

Expected: `Sessions/`, `Threads/`, `Weekly/` directories present.

---

### Task 2: Migrate Existing Journals to Sessions/

**Files:**
- Move: `~/obsidian/Agent Journals/*.md` → `~/obsidian/Agent Journals/Sessions/`
- Modify: each moved file (add missing frontmatter fields)

- [ ] **Step 1: Move existing journal files to Sessions/**

```bash
cd ~/obsidian/"Agent Journals"
for f in *.md; do
  [ -f "$f" ] && mv "$f" "Sessions/$f"
done
```

- [ ] **Step 2: Verify files moved**

```bash
ls ~/obsidian/"Agent Journals"/Sessions/
```

Expected: all 6 existing journal files now in Sessions/.

- [ ] **Step 3: Add missing frontmatter to each file**

For each file, use `notesmd frontmatter` to add the `threads`, `tools_installed`, and `tags` fields. Read each file first to determine appropriate values, then update. Example for one file:

```bash
# Read the file to determine appropriate thread/tag values
notesmd print "Agent Journals/Sessions/2026-03-17 - Superpowers Plugin Installation"

# Add frontmatter fields
notesmd frontmatter "Agent Journals/Sessions/2026-03-17 - Superpowers Plugin Installation" \
  --edit --key "threads" --value "Obsidian Agent Infrastructure"
notesmd frontmatter "Agent Journals/Sessions/2026-03-17 - Superpowers Plugin Installation" \
  --edit --key "tags" --value "tooling, plugins"
```

Repeat for all 6 files. Read each file, infer threads/tags from content.

- [ ] **Step 4: Verify frontmatter on one file**

```bash
notesmd frontmatter "Agent Journals/Sessions/2026-03-17 - Superpowers Plugin Installation" --print
```

Expected: YAML with `session`, `date`, `project`, `threads`, `tags` fields.

- [ ] **Step 5: Commit**

```bash
# Nothing to commit — these are in the Obsidian vault, not a git repo
```

---

### Task 3: Write Transcript Extractor Script

The `/journal` skill needs to read session transcripts. JSONL files can be hundreds of lines with thinking blocks, tool inputs, and other noise. This script extracts a readable conversation summary.

**Files:**
- Create: `~/.claude/scripts/extract-transcript.sh`

- [ ] **Step 1: Create scripts directory**

```bash
mkdir -p ~/.claude/scripts
```

- [ ] **Step 2: Write the extractor script**

Create `~/.claude/scripts/extract-transcript.sh`:

```bash
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
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x ~/.claude/scripts/extract-transcript.sh
```

- [ ] **Step 4: Test against a known session**

```bash
# Find the most recent session JSONL
LATEST=$(ls -t ~/.claude/projects/-Users-gnat-Source-Personal-vaultbot3000/*.jsonl 2>/dev/null | head -1)
~/.claude/scripts/extract-transcript.sh "$LATEST" | head -50
```

Expected: alternating `## User` and `## Assistant` sections with readable text. No thinking blocks, no raw JSON tool inputs.

- [ ] **Step 5: Test edge case — empty/missing file**

```bash
~/.claude/scripts/extract-transcript.sh /tmp/nonexistent.jsonl 2>&1
```

Expected: error message, non-zero exit.

- [ ] **Step 6: Commit**

```bash
cd ~/Source/Personal/vaultbot3000
git add ~/.claude/scripts/extract-transcript.sh
git commit -m "feat: add transcript extractor script for agent journals"
```

Note: if `~/.claude/scripts/` is outside the repo, skip the commit — the file lives in Claude config, not the project.

---

### Task 4: Write the /journal Skill

**Files:**
- Create: `~/.claude/skills/journal/SKILL.md`

- [ ] **Step 1: Write the skill file**

Create `~/.claude/skills/journal/SKILL.md`:

```markdown
---
name: journal
description: Use when a session ends or when you want to write a journal entry for a Claude Code session into the Obsidian vault
---

# Write Session Journal

Write a journal entry for a Claude Code session into `~/obsidian/Agent Journals/Sessions/`.

## Required Sub-Skill

**REQUIRED:** Use the `nat-write` skill for all prose. The journal must sound like Nat wrote it.

## Input

This skill can be invoked two ways:

1. **Automatically via session-end hook** — the hook passes a session JSONL path as an argument
2. **Manually** — user types `/journal` and optionally provides a session ID or path

If no session is specified, journal the current session (read its own JSONL).

## Process

1. **Find the session transcript.** If a path was provided, use it. Otherwise, find the most recent JSONL in `~/.claude/projects/`:

   ```bash
   ls -t ~/.claude/projects/*/*.jsonl | head -1
   ```

2. **Extract readable conversation.** Run the transcript extractor:

   ```bash
   ~/.claude/scripts/extract-transcript.sh <path-to-jsonl>
   ```

   Read the output to understand what happened in the session.

3. **Get session metadata.** Extract the session ID, project path, and start time from the JSONL:

   ```bash
   head -1 <path-to-jsonl> | jq '{sessionId, cwd, timestamp}'
   ```

4. **Check for existing journals today.** List files matching today's date in Sessions/ to determine the letter suffix:

   ```bash
   ls ~/obsidian/"Agent Journals"/Sessions/$(date +%Y-%m-%d)* 2>/dev/null
   ```

   If no files: no suffix. If files exist: use next letter (a, b, c...).

5. **Write the journal.** Use `notesmd create` to write the journal entry. The content must follow this exact format:

   **Frontmatter:**
   ```yaml
   ---
   session: <8-char session ID prefix>
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
   ```markdown
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

6. **Write the file:**

   ```bash
   notesmd create "Agent Journals/Sessions/<filename>" --content "<content>"
   ```

   Where filename follows: `YYYY-MM-DD - Title.md` (with optional letter suffix).

## Thread Naming

When proposing thread names in the `threads` frontmatter field:

- Name the thread after the **intent**, not the directory. "Meeting Transcription Pipeline" not "/Users/gnat/Source"
- Check existing thread files in `~/obsidian/Agent Journals/Threads/` and reuse names when the work is a continuation
- A session can belong to multiple threads
- Short sessions (quick questions, config changes) can have a generic thread like "Misc" or a specific one — use judgment

## Voice

ALL prose MUST follow the `nat-write` skill. Key reminders:
- Direct, no throat-clearing
- Parenthetical asides for editorial color
- Honest about mess, mark open questions with [brackets]
- Concrete: real names, real paths, real error messages
- No AI summary voice ("In this session, we successfully...")

## Recursion Guard

If the environment variable `AGENT_JOURNAL_SESSION=1` is set, this is a journal-writing session. Do NOT write a journal for it — just exit with a message: "Skipping journal — this is a journal-writing session."
```

- [ ] **Step 2: Verify skill appears in skill list**

Restart Claude Code (or start new session) and check that `/journal` appears in the available skills list.

- [ ] **Step 3: Test the skill manually**

In a Claude Code session, invoke `/journal` and specify a recent session. Verify:
- File created in `~/obsidian/Agent Journals/Sessions/`
- Frontmatter has all required fields
- Body follows the section structure
- Voice matches nat-write (no AI summary voice)
- Thread names are reasonable

- [ ] **Step 4: Verify in Obsidian**

Open Obsidian and check the new journal entry renders correctly, frontmatter is parsed, and it looks right.

---

### Task 5: Write Session-End Hook

**Files:**
- Create: `~/.claude/scripts/journal-hook.sh`
- Modify: `~/.claude/settings.json` (add hooks config)

- [ ] **Step 1: Write the hook script**

Create `~/.claude/scripts/journal-hook.sh`:

```bash
#!/usr/bin/env bash
# Session-end hook: launches a new Claude session to write a journal entry.
# Skips if this is already a journal-writing session (recursion guard).

set -euo pipefail

# Recursion guard
if [ "${AGENT_JOURNAL_SESSION:-}" = "1" ]; then
  exit 0
fi

# Find the most recently modified session JSONL across all projects
LATEST_JSONL=$(ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1)

if [ -z "$LATEST_JSONL" ]; then
  echo '{"continue": true}'
  exit 0
fi

# Extract session ID for logging
SESSION_ID=$(head -1 "$LATEST_JSONL" | jq -r '.sessionId // "unknown"' 2>/dev/null)

# Launch journal-writing session in background
# The AGENT_JOURNAL_SESSION env var prevents recursion
AGENT_JOURNAL_SESSION=1 nohup claude --print -p "Use the /journal skill to write a journal entry for session at: $LATEST_JSONL" \
  > /tmp/agent-journal-last.log 2>&1 &
disown

echo '{"continue": true}'
exit 0
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x ~/.claude/scripts/journal-hook.sh
```

- [ ] **Step 3: Add hook to settings.json**

Add a `hooks` key to `~/.claude/settings.json`. The hooks go at the top level alongside `permissions`:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/journal-hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Important:** Merge this into the existing settings.json — don't overwrite the permissions and plugins config.

- [ ] **Step 4: Test the hook script standalone**

```bash
# Test without recursion guard (should find JSONL and print continue)
bash ~/.claude/scripts/journal-hook.sh

# Test with recursion guard (should exit silently)
AGENT_JOURNAL_SESSION=1 bash ~/.claude/scripts/journal-hook.sh
```

- [ ] **Step 5: End-to-end test**

Start a short Claude Code session, do something minimal, then exit. Check:
1. `/tmp/agent-journal-last.log` shows the journal skill ran
2. A new file appeared in `~/obsidian/Agent Journals/Sessions/`

If the hook doesn't fire, check `~/.claude/settings.json` syntax and restart Claude Code.

---

### Task 6: Write the /reflect Skill

**Files:**
- Create: `~/.claude/skills/reflect/SKILL.md`

- [ ] **Step 1: Write the skill file**

Create `~/.claude/skills/reflect/SKILL.md`:

```markdown
---
name: reflect
description: Use when you want to synthesize session journals into thread documents or generate a weekly digest — reads Agent Journals in Obsidian and produces cross-session analysis
---

# Reflect on Sessions

Read session journals and produce thread documents and/or weekly digests.

## Required Sub-Skill

**REQUIRED:** Use the `nat-write` skill for all prose.

## Usage

- `/reflect` — update all thread documents based on recent sessions
- `/reflect weekly` — generate a weekly digest for the current or most recent week

## Thread Reflection Process

1. **Read all session journals:**

   ```bash
   ls ~/obsidian/"Agent Journals"/Sessions/
   ```

   For each file, read it with `notesmd print "Agent Journals/Sessions/<filename>"`.

2. **Read existing thread documents:**

   ```bash
   ls ~/obsidian/"Agent Journals"/Threads/
   ```

   For each file, read it with `notesmd print "Agent Journals/Threads/<filename>"`.

3. **Group sessions by thread.** Parse the `threads` frontmatter from each session journal. Build a map of thread name → list of sessions.

4. **For each thread, create or update its document.**

   **New thread** (no existing file): create with this structure:

   ```markdown
   ---
   thread: <Thread Name>
   status: active
   started: <date of earliest session>
   last_updated: <today>
   sessions:
     - "[[<session filename without .md>]]"
   ---

   # <Thread Name>

   ## Current Status
   <synthesize current state from all sessions in this thread>

   ## Open Questions
   - <unresolved items from sessions>

   ## Key Decisions
   - <decisions made across sessions>

   ---

   ## YYYY-MM-DD Update
   <summary of what happened in the most recent session(s)>
   ```

   **Existing thread** (file already exists): update the top sections (Current Status, Open Questions, Key Decisions) based on new session data. Prepend a new dated update section below the `---` separator. Add new session wikilinks to the `sessions` frontmatter list. Update `last_updated` and `status`.

5. **Infer thread status:**
   - `active` — sessions in the last 7 days
   - `paused` — last session 8–30 days ago
   - `complete` — session explicitly says work is done
   - `abandoned` — last session >30 days ago with open questions

   User can always override by editing the frontmatter.

6. **Write files** using `notesmd create` with `--overwrite` for existing threads, plain create for new ones.

## Weekly Digest Process

When invoked with `/reflect weekly`:

1. **Determine the week.** Use the current ISO week, or if today is Monday, use the previous week.

2. **Read all sessions from that week.** Filter `Sessions/` files by date prefix.

3. **Read current thread state** from `Threads/`.

4. **Write the digest** to `Weekly/YYYY-WNN.md`:

   ```markdown
   ---
   week: YYYY-WNN
   dates: YYYY-MM-DD to YYYY-MM-DD
   session_count: <N>
   active_threads:
     - "[[Thread Name]]"
   ---

   # Week NN: Mon DD–DD

   ## Overview
   <2-4 sentences — opinionated summary of the week. What was the theme?
   How did it feel? Use Nat's voice.>

   ## Thread Progress
   - **Thread Name** — <one-line narrative of what moved>. (<N sessions>)

   ## Recurring Patterns
   - <friction or habits that appeared in multiple sessions>

   ## Improvement Proposals
   - **<Proposal>** — <description> (surfaced Nx)

   ## Sessions This Week
   - [[session filename]]
   ```

5. **Aggregate improvement ideas.** Scan the `## Improvement Ideas` section of each session journal. Count how many times each idea (or similar ideas) have been proposed across all time, not just this week.

6. **Write file** using `notesmd create` with `--overwrite` if updating an existing week.

## Voice

ALL prose MUST follow the `nat-write` skill. The weekly Overview especially should sound like Nat reflecting on his week, not an AI report.
```

- [ ] **Step 2: Verify skill appears in skill list**

Start a new Claude Code session. Check that `/reflect` appears.

- [ ] **Step 3: Test thread reflection**

Run `/reflect` in a Claude Code session. Verify:
- Thread documents created in `~/obsidian/Agent Journals/Threads/`
- Thread names match the `threads` frontmatter in session journals
- Current Status section synthesizes across sessions
- Wikilinks in frontmatter are correct
- Status field is reasonable

- [ ] **Step 4: Test weekly digest**

Run `/reflect weekly`. Verify:
- File created at `~/obsidian/Agent Journals/Weekly/2026-W13.md` (or appropriate week)
- All sessions from the week are listed
- Thread progress is narrative, not a list
- Recurring patterns section has real observations
- Voice matches nat-write

---

### Task 7: Set Up Weekly Scheduled Agent

**Files:**
- Create: scheduled trigger via `/schedule`

- [ ] **Step 1: Check if scheduling is available**

```bash
# In Claude Code session:
/schedule list
```

If `/schedule` is available, proceed. If not, fall back to a system cron.

- [ ] **Step 2: Create the weekly schedule**

Option A — Claude Code scheduled agent:
```
/schedule create --cron "0 18 * * 0" --name "weekly-journal-digest" \
  --prompt "Use the /reflect skill with 'weekly' argument to generate this week's digest in ~/obsidian/Agent Journals/Weekly/"
```

Option B — System cron (fallback):
```bash
# Add to crontab
(crontab -l 2>/dev/null; echo '0 18 * * 0 AGENT_JOURNAL_SESSION=1 claude --print -p "Use the /reflect skill with weekly argument to generate this weeks digest" >> /tmp/weekly-digest.log 2>&1') | crontab -
```

Sunday at 6pm in either case.

- [ ] **Step 3: Test the scheduled prompt manually**

Run the prompt manually to verify it works before waiting for the cron:

```
claude --print -p "Use the /reflect skill with 'weekly' argument to generate this week's digest"
```

Check that `~/obsidian/Agent Journals/Weekly/` gets a new file.

- [ ] **Step 4: Verify schedule is registered**

```
/schedule list
```

Expected: `weekly-journal-digest` appears with cron `0 18 * * 0`.

---

### Task 8: End-to-End Verification

- [ ] **Step 1: Run a short test session**

Start a Claude Code session, do something simple (e.g., ask a question about a file), then exit.

- [ ] **Step 2: Verify journal was auto-created**

```bash
ls -lt ~/obsidian/"Agent Journals"/Sessions/ | head -3
```

Expected: a new journal file for today's date.

- [ ] **Step 3: Check journal content quality**

Read the auto-created journal. Verify:
- Frontmatter is complete and valid
- Thread names are reasonable
- Voice sounds like Nat, not AI
- Sections are all present

- [ ] **Step 4: Run /reflect and verify threads**

```
/reflect
```

Check `Threads/` for updated or new thread documents.

- [ ] **Step 5: Run /reflect weekly and verify digest**

```
/reflect weekly
```

Check `Weekly/` for the digest file.

- [ ] **Step 6: Verify Obsidian graph**

Open Obsidian. Check:
- Wikilinks between Sessions and Threads work (click through)
- Graph view shows connections
- Frontmatter renders in reading view
