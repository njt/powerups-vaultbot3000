---
name: reflect
description: Use when you want to synthesize session journals into thread documents or generate a weekly digest — reads Agent Journals in Obsidian and produces cross-session analysis
---

# Reflect on Sessions

Read session journals and produce thread documents and/or weekly digests.

## Vault Path

Read the vault path from the `OBSIDIAN_VAULT` environment variable. If not set, default to `~/obsidian`. All paths below use `$VAULT` as shorthand for this resolved path.

```bash
VAULT="${OBSIDIAN_VAULT:-$HOME/obsidian}"
```

## Voice

If the user has a custom writing voice skill (e.g. a `nat-write` or similar style skill), use it for all prose. Otherwise, write in a direct, concrete style: no throat-clearing, no AI summary voice, honest about mess.

## Usage

- /reflect — update all thread documents based on recent sessions
- /reflect weekly — generate a weekly digest for the current or most recent week

## Thread Reflection Process

1. **Read all session journals:**

   ```bash
   ls "$VAULT"/"Agent Journals"/Sessions/
   ```

   Read each file to understand what happened.

2. **Read existing thread documents:**

   ```bash
   ls "$VAULT"/"Agent Journals"/Threads/
   ```

   Read each file to understand current thread state.

3. **Group sessions by thread.** Parse the threads frontmatter from each session journal. Build a map of thread name → list of sessions.

4. **For each thread, create or update its document.**

   **New thread** (no existing file): create with this structure:

   ```
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

   **Existing thread** (file already exists): update the top sections (Current Status, Open Questions, Key Decisions) based on new session data. Prepend a new dated update section below the --- separator. Add new session wikilinks to the sessions frontmatter list. Update last_updated and status.

5. **Infer thread status:**
   - active — sessions in the last 7 days
   - paused — last session 8–30 days ago
   - complete — session explicitly says work is done
   - abandoned — last session >30 days ago with open questions

   User can always override by editing the frontmatter.

6. **Write files** to `$VAULT/Agent Journals/Threads/`. If `notesmd` is available, use `notesmd create` with `--overwrite` for existing threads, plain `create` for new ones. Otherwise, write files directly.

## Weekly Digest Process

When invoked with /reflect weekly:

1. **Determine the week.** Use the current ISO week, or if today is Monday, use the previous week.

2. **Read all sessions from that week.** Filter Sessions/ files by date prefix.

3. **Read current thread state** from Threads/.

4. **Write the digest** to Weekly/YYYY-WNN.md:

   ```
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

5. **Aggregate improvement ideas.** Scan the ## Improvement Ideas section of each session journal. Count how many times each idea (or similar ideas) have been proposed across all time, not just this week.

6. **Write file** to `$VAULT/Agent Journals/Weekly/`. If `notesmd` is available, use `notesmd create` with `--overwrite` if updating an existing week. Otherwise, write the file directly.

The weekly Overview especially should sound like someone reflecting on their week, not an AI report.
