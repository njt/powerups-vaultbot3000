# powerups-vaultbot3000

> Automated journaling and reflection for Claude Code sessions — every session gets a structured journal entry in your Obsidian vault, with thread tracking and weekly digests for humans to read.

## Problem Statement

You run dozens of Claude Code sessions a week across multiple projects. Without a record, context evaporates between sessions — decisions get re-litigated, dead ends get re-explored, improvement ideas get lost. Manual notes don't happen.

The current state is nothing: Claude Code has no built-in session history visible to the user. The session transcripts exist as JSONL files in `~/.claude/projects/` but they're machine-format, voluminous, and not designed for human consumption.

Success looks like: a searchable, browsable archive of what you did in each session, organized by lines of work, with weekly zoom-outs that surface patterns you'd miss in the day-to-day. All written for humans, queryable in Obsidian, and requiring zero effort from the user beyond installing the plugin.

## Actors

| ID | Actor | Description | Goal |
|----|-------|-------------|------|
| A1 | User | A Claude Code user who runs multiple sessions per week across projects | Understand what happened across sessions without manual note-taking |
| A2 | Scheduled Agent | A cron-triggered background process (Claude CLI in --print mode) | Produce weekly digests and catch up on missed journals automatically |

## Glossary

### Terms

| Term | Aliases | Definition |
|------|---------|------------|
| Session journal | journal, session entry | A markdown file recording what happened in a single Claude Code session |
| Thread | thread document | A markdown file tracking a line of work across multiple sessions, named by intent |
| Weekly digest | digest, weekly | A markdown file summarizing a week's sessions, thread progress, and patterns |
| Vault | markdown folder | A markdown folder where all journal output is written. Typically managed by Obsidian, but the plugin writes plain markdown and works with any markdown folder or viewer. |
| Interactive session | CLI session, desktop session | A Claude Code session started by a human (via CLI or Claude Desktop), as opposed to subagent or --print sessions |
| Transcript | session transcript, JSONL | The raw session log stored by Claude Code in ~/.claude/projects/ |
| Reflect | reflection | The process of reading session journals and synthesizing thread documents or weekly digests |

### Domain Quirks

- "Thread" in this context has nothing to do with conversation threads or chat threads. It means a line of work spanning multiple sessions, named by intent (e.g. "Meeting Transcription Pipeline"), not by project directory.
- "Interactive session" is determined by the `entrypoint` field in the JSONL transcript. Only `cli` and `claude-desktop` entrypoints count. Subagents (`sdk-cli`) and `--print` invocations are excluded even though they produce transcripts.
- Session journals are for humans to read, not for RAG or agent consumption during coding sessions. They are not a memory system.

## Functional Requirements

### FR-01: Automatic session journaling
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to have a record of every coding session without manual effort, the user needs the system to automatically write a journal entry when each session ends.
- **Description:** When an interactive Claude Code session ends, the system writes a structured journal entry to the vault. The user does not need to take any action.
- **Rationale:** The core value proposition — if the user has to remember to journal, they won't.
- **Acceptance Criteria:**
  - [ ] A journal entry is created in the vault when an interactive session ends
  - [ ] Non-interactive sessions (subagents, --print invocations) are not journaled
  - [ ] The journal-writing process does not journal itself (no recursive journaling)
  - [ ] Journal creation does not block the user from starting their next session
- **Scenarios:**
  ```gherkin
  Scenario: The one where a normal CLI session ends
    Given a user finishes a 45-minute Claude Code CLI session working on a transcription pipeline
    When the session ends
    Then a journal entry appears in the vault's Sessions/ folder
    And the journal describes what happened in the session
    And the user did not have to do anything

  Scenario: The one where a subagent session ends
    Given a Claude Code subagent session completes (entrypoint: sdk-cli)
    When the session ends
    Then no journal entry is created

  Scenario: The one where the journal-writing session ends
    Given the background Claude process that writes journal entries finishes its work
    When that session ends
    Then no journal entry is created for the journal-writing session
  ```

### FR-02: Manual session journaling
- **Status:** settled
- **Priority:** should
- **Actor:** A1
- **Intent:** In order to journal a specific session or re-journal a session, the user needs to be able to trigger journaling manually.
- **Description:** The user can invoke the journal skill directly, optionally specifying a session JSONL path. If no session is specified, the current session is journaled.
- **Rationale:** Covers cases where the hook missed a session, or the user wants to re-journal.
- **Acceptance Criteria:**
  - [ ] User can invoke the journal skill and get a journal entry written
  - [ ] User can specify a particular session to journal
  - [ ] If no session is specified, the current session is journaled

### FR-03: Session journal content — structured metadata
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to search, filter, and query journals in Obsidian, the user needs each journal to have structured YAML frontmatter with consistent fields.
- **Description:** Each session journal includes YAML frontmatter with: session ID (8-char prefix), date, project path, thread names, tools installed (if any), and topic tags.
- **Rationale:** Frontmatter enables Obsidian Dataview queries and filtering. The session ID links back to the raw transcript.
- **Acceptance Criteria:**
  - [ ] Every journal has YAML frontmatter with session, date, project, threads, and tags fields
  - [ ] tools_installed is present when software was installed or configured in the session
  - [ ] Thread names are intent-based, not directory paths
  - [ ] Tags are topic-level (e.g. "transcription", "local-llm"), not implementation-level
- **Scenarios:**
  ```gherkin
  Scenario: The one where a session installs software
    Given a session where the user installed Ollama and configured qwen3:8b
    When the journal is written
    Then the frontmatter tools_installed field lists "Ollama" and "qwen3:8b"
    And the threads field names the work by intent (e.g. "Meeting Transcription Pipeline")
    And the threads field does not contain a filesystem path
  ```

### FR-04: Session journal content — narrative body
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to understand what happened in a session without re-reading the transcript, the user needs a human-readable narrative covering what happened, what worked, what didn't, and what was learned.
- **Description:** The journal body includes sections for: summary (1-3 sentences), what happened (narrative), what worked, what didn't, learnings, and improvement ideas (if any). Sections can be short or skipped when there's nothing to say.
- **Rationale:** These sections give the human reader what they actually want — not a transcript rehash, but a distilled account with editorial judgment.
- **Acceptance Criteria:**
  - [ ] Every journal has a Summary section (1-3 sentences)
  - [ ] Every journal has a What Happened narrative section
  - [ ] What Worked and What Didn't sections capture the session honestly
  - [ ] Learnings captures durable takeaways
  - [ ] Improvement Ideas section appears only when there are genuine ideas
  - [ ] Unresolved questions are marked with [bracket notes]
- **Scenarios:**
  ```gherkin
  Scenario: The one where a session hit a dead end
    Given a session where the user tried three approaches to fix a bug and only the third worked
    When the journal is written
    Then the What Didn't section describes the two failed approaches
    And the What Worked section describes the successful approach
    And the Learnings section captures why the third approach worked

  Scenario: The one where there are no improvement ideas
    Given a session that was straightforward with no friction
    When the journal is written
    Then the Improvement Ideas section is omitted
  ```

### FR-05: Secrets redaction
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to keep the vault safe to share or sync, the user needs the system to never include API keys, passwords, tokens, or credentials in journal entries.
- **Description:** The journal skill scans for secrets in the transcript and omits them from the journal. If a secret is relevant to the narrative (e.g. "configured the API key"), the action is mentioned without reproducing the value.
- **Rationale:** Obsidian vaults are often synced to cloud storage or shared. Secrets in journals are a security risk.
- **Acceptance Criteria:**
  - [ ] No API keys, passwords, tokens, or credentials appear in journal entries
  - [ ] Actions involving secrets are described without the secret value
- **Scenarios:**
  ```gherkin
  Scenario: The one where an API key was configured
    Given a session where the user set ANTHROPIC_API_KEY=sk-ant-abc123...
    When the journal is written
    Then the journal mentions that the API key was configured
    And the journal does not contain the key value "sk-ant-abc123"
  ```

### FR-06: De minimis filtering
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to avoid cluttering the vault with noise, the user needs trivial sessions (test pings, accidental starts) to be skipped.
- **Description:** If a session has no substance worth recording, no journal is written. The check is semantic (was there meaningful work?) not mechanical (line count threshold).
- **Rationale:** Without this, the vault fills with empty entries that dilute the useful ones.
- **Acceptance Criteria:**
  - [ ] Sessions with no real work (test ping, accidental start, single trivial question) produce no journal
  - [ ] Short sessions with a meaningful decision or insight are still journaled
  - [ ] The filtering is based on substance, not transcript length
- **Scenarios:**
  | Session content | Journaled? | Why |
  |----------------|-----------|-----|
  | User typed "hi" then exited | No | No substance |
  | User asked one question about a config flag and got an answer that changed their approach | Yes | Meaningful decision |
  | User started a session, ran one command, then exited | No | No substance |
  | 10-minute session where a critical bug was identified | Yes | Meaningful insight |

### FR-07: Multiple sessions per day
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to keep journals distinct when running multiple sessions in a day, the user needs each session to get its own file with a unique name.
- **Description:** When multiple sessions are journaled on the same day, filenames get letter suffixes (a, b, c, etc.) to remain unique.
- **Rationale:** Users often run 3-5+ sessions per day. Without suffixes, files would collide.
- **Acceptance Criteria:**
  - [ ] First session of the day: `YYYY-MM-DD - Title.md`
  - [ ] Second session: `YYYY-MM-DDa - Title.md` (or similar lettered scheme)
  - [ ] Each session gets its own distinct file
- **Scenarios:**
  | Day's sessions | Resulting filenames |
  |---------------|-------------------|
  | 1 session | `2026-03-22 - Pipeline Setup.md` |
  | 3 sessions | `2026-03-22 - Pipeline Setup.md`, `2026-03-22a - Bug Fix.md`, `2026-03-22b - Config Review.md` |

### FR-08: Thread synthesis
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to see the arc of a line of work across sessions, the user needs thread documents that synthesize multiple session journals into a coherent narrative.
- **Description:** The reflect skill reads session journals, groups them by thread name, and creates or updates thread documents with current status, open questions, key decisions, and a dated update log.
- **Rationale:** Individual session journals are useful but don't show the big picture. Threads answer "where am I on this project?"
- **Acceptance Criteria:**
  - [ ] Thread documents are created from session journal thread names
  - [ ] Each thread document synthesizes all sessions belonging to that thread
  - [ ] Thread documents have current status, open questions, and key decisions sections
  - [ ] Thread documents have a dated update log that grows over time
  - [ ] Sessions link to threads and threads link back to sessions (via Obsidian wikilinks)
  - [ ] Thread names proposed by journals can be edited by the user; the next reflect pass regroups
  - [ ] Thread renames are a manual process: edit session frontmatter and rename the thread file
- **Scenarios:**
  ```gherkin
  Scenario: The one where a new thread is created
    Given three session journals all tagged with thread "Meeting Transcription Pipeline"
    And no existing thread document for "Meeting Transcription Pipeline"
    When the user runs reflect
    Then a thread document "Meeting Transcription Pipeline.md" is created in Threads/
    And the Current Status synthesizes the state across all three sessions
    And the sessions frontmatter lists wikilinks to all three session journals

  Scenario: The one where an existing thread is updated
    Given an existing thread document for "Meeting Transcription Pipeline" covering sessions from last week
    And two new session journals tagged with "Meeting Transcription Pipeline"
    When the user runs reflect
    Then the Current Status is updated to reflect the new sessions
    And a new dated update section is added to the update log
    And the new sessions are added to the sessions frontmatter list
    And existing Key Decisions are preserved (not deleted)
  ```

### FR-09: Thread status inference
- **Status:** settled
- **Priority:** should
- **Actor:** A1
- **Intent:** In order to see at a glance which threads are active vs stale, the user needs the system to infer thread status from session recency.
- **Description:** Thread status is inferred as: active (sessions in the last 7 days), paused (8-30 days), complete (session says work is done), abandoned (>30 days with open questions). The user can override by editing frontmatter.
- **Rationale:** Saves the user from manually maintaining status. The rules are simple enough to be predictable.
- **Acceptance Criteria:**
  - [ ] Status is inferred from session dates and content
  - [ ] User can override the inferred status by editing the frontmatter
  - [ ] Status values are: active, paused, complete, abandoned

### FR-10: Weekly digest
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to see a bigger-picture zoom-out of a week's work, the user needs a weekly digest that summarizes thread progress, surfaces recurring patterns, and tracks improvement proposals.
- **Description:** The weekly digest covers: opinionated overview of the week, thread progress (narrative per thread), recurring patterns across sessions, improvement proposals with frequency counts, and a list of sessions.
- **Rationale:** The weekly digest is the "what the hell DID I do this week?" answer. Patterns and repeated improvement proposals are invisible in individual sessions.
- **Acceptance Criteria:**
  - [ ] Digest covers one ISO week
  - [ ] Overview is an opinionated 2-4 sentence summary, not a dry list
  - [ ] Thread progress is narrative (what moved, what's stuck) not a bullet list of sessions
  - [ ] Recurring patterns surface friction or habits appearing in multiple sessions
  - [ ] Improvement proposals are aggregated across all time with frequency counts
  - [ ] All sessions from the week are listed with wikilinks
- **Scenarios:**
  ```gherkin
  Scenario: The one where an improvement idea keeps recurring
    Given the user has proposed "create a /transcribe skill" in 3 separate session journals over 2 weeks
    When the weekly digest is generated
    Then the Improvement Proposals section lists "/transcribe skill" with "(surfaced 3x)"
    And the frequency count reflects all-time occurrences, not just this week

  Scenario: The one where the digest is generated on Monday
    Given today is Monday
    When the user runs reflect weekly
    Then the digest covers the previous week (Monday-Sunday), not the current week
  ```

### FR-11: Scheduled weekly digest
- **Status:** settled
- **Priority:** should
- **Actor:** A2
- **Intent:** In order to get weekly digests without remembering to run reflect, the scheduled agent needs to produce the digest automatically on a weekly cadence.
- **Description:** A cron job runs weekly (Sunday morning) to generate the weekly digest. The digest appears in the vault without user action.
- **Rationale:** Same principle as automatic journaling — if it requires user action, it won't happen.
- **Acceptance Criteria:**
  - [ ] Weekly digest is generated automatically on a weekly schedule
  - [ ] The scheduled run does not require user intervention

### FR-12: Catch-up for missed journals
- **Status:** settled
- **Priority:** should
- **Actor:** A2
- **Intent:** In order to maintain a complete journal archive even when the session-end hook fails, the system needs to find and backfill missed sessions.
- **Description:** A weekly catch-up process finds interactive sessions from the past 7 days that don't have corresponding journal entries and journals them. Sessions are matched by session ID prefix.
- **Rationale:** The session-end hook can miss sessions due to reboots, crashes, or hook failures. Without catch-up, the archive has gaps.
- **Acceptance Criteria:**
  - [ ] Sessions from the past 7 days without journals are identified and journaled
  - [ ] Non-interactive sessions are excluded from catch-up
  - [ ] Already-journaled sessions are not re-journaled
  - [ ] Trivial sessions (very short transcripts) are excluded
- **Scenarios:**
  ```gherkin
  Scenario: The one where the hook missed sessions due to a reboot
    Given 5 interactive CLI sessions were run during the week
    And 3 have journal entries but 2 were missed (machine rebooted before hook fired)
    When the weekly catch-up runs
    Then journal entries are created for the 2 missed sessions
    And the 3 already-journaled sessions are not re-journaled
  ```

### FR-13: Cross-document linking via wikilinks
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to navigate between sessions and threads, the user needs links connecting the documents.
- **Description:** Thread documents list sessions as `[[wikilinks]]` in frontmatter. Weekly digests list sessions and threads as wikilinks. The core output is standard markdown; wikilinks enable graph view and backlink navigation when Obsidian is used, and are still useful as plain document references in other markdown tools.
- **Rationale:** Cross-linking between sessions, threads, and digests is essential for navigating the archive regardless of the markdown tool used. Wikilinks are the standard format in this ecosystem and work natively in Obsidian.
- **Acceptance Criteria:**
  - [ ] Thread documents reference sessions via `[[wikilinks]]`
  - [ ] Weekly digests reference sessions and threads via `[[wikilinks]]`
  - [ ] Links are navigable in Obsidian's graph view when Obsidian is used
- **Scenarios:**
  ```gherkin
  Scenario: The one where thread and session are linked
    Given a thread document for "Meeting Transcription Pipeline"
    And three session journals tagged with that thread
    When the reflect skill creates the thread document
    Then the thread document's frontmatter sessions list contains wikilinks to all three session journals
    And each wikilink uses the session filename without .md extension
  ```

### FR-14: Transcript extraction
- **Status:** settled
- **Priority:** must
- **Actor:** A1 (indirectly — this enables FR-01 and FR-04)
- **Intent:** In order to write meaningful journals, the system needs to extract a readable conversation from the raw JSONL session transcript.
- **Description:** The system extracts user messages and assistant text responses from the JSONL transcript, including tool names used but excluding tool input/output details, thinking blocks, and system messages.
- **Rationale:** Raw JSONL transcripts are thousands of lines of machine-format data. The journal skill needs a readable summary to work from.
- **Acceptance Criteria:**
  - [ ] User messages and assistant text are extracted
  - [ ] Tool names are included (so the reader knows what happened)
  - [ ] Thinking blocks, tool inputs/outputs, and system messages are excluded
  - [ ] The output is readable by the journal-writing process
- **Scenarios:**
  ```gherkin
  Scenario: The one where a session has mixed content types
    Given a session transcript containing user messages, assistant text, tool use (Bash, Read), and thinking blocks
    When the transcript is extracted
    Then user messages appear as readable text
    And assistant text appears as readable text
    And tool uses appear as "[tool: Bash]", "[tool: Read]" etc.
    And tool inputs, tool outputs, thinking blocks, and system messages are excluded
  ```

### FR-15: Voice requirements
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to get journals and digests that are pleasant to read (not corporate AI slop), the user needs the output to follow a specific writing voice.
- **Description:** All prose uses a direct, concrete style: no throat-clearing, no AI summary voice, honest about mess, parenthetical asides for editorial color. If the user has a custom writing voice skill, it is used. Otherwise, the system defaults to this style.
- **Rationale:** The journals are for human reading. AI-sounding prose ("In this session, we successfully...") undermines the value.
- **Acceptance Criteria:**
  - [ ] No "In this session, we successfully..." style phrasing
  - [ ] No corporate boilerplate or hedging language
  - [ ] Concrete details: real names, real tools, real error messages
  - [ ] Open questions marked with [brackets]
  - [ ] Custom voice skill used when available
  - [ ] Default voice is direct and concrete when no custom skill exists
- **Scenarios:**
  | Phrase | Acceptable? | Why |
  |--------|------------|-----|
  | "Got Ollama running, transcribed a 96-minute Zoom call" | Yes | Direct, concrete |
  | "In this session, we successfully configured the transcription pipeline" | No | AI summary voice |
  | "Several challenges were encountered and resolved" | No | Vague, corporate |
  | "qwen3's thinking mode burns 30+ minutes on large inputs (still unsolved)" | Yes | Concrete, honest, parenthetical aside |

### FR-16: Configurable vault path
- **Status:** settled
- **Priority:** must
- **Actor:** A1
- **Intent:** In order to use the plugin with any Obsidian vault location, the user needs to be able to configure where journals are written.
- **Description:** The vault path is configurable via the `OBSIDIAN_VAULT` environment variable, with a sensible default.
- **Rationale:** Different users have their vaults in different locations.
- **Acceptance Criteria:**
  - [ ] Vault path is read from `OBSIDIAN_VAULT` environment variable
  - [ ] A default path is used when the variable is not set
  - [ ] All components (hook, skills, cron jobs) respect the configured path
- **Scenarios:**
  ```gherkin
  Scenario: The one where vault path is customized
    Given OBSIDIAN_VAULT is set to /home/user/my-notes
    When a session ends and is journaled
    Then the journal file appears in /home/user/my-notes/Agent Journals/Sessions/
    And no files are written to ~/obsidian/
  ```

## Constraints

### C-01: Unix-only platform
- **Status:** settled
- **Description:** The plugin runs on macOS and Linux only. Windows is not supported.
- **Rationale:** The plugin depends on shell scripts, cron, nohup/disown, and bash semantics that don't translate to Windows.

### C-02: Claude Code plugin system
- **Status:** settled
- **Description:** The plugin must conform to the Claude Code plugin architecture — skills as SKILL.md files, hooks as hooks.json, scripts referenced by the plugin.
- **Rationale:** This is a Claude Code plugin; it has no other runtime.

### C-03: Non-blocking hook execution
- **Status:** settled
- **Description:** The session-end hook must complete within 10 seconds. The actual journaling work runs in a detached background process.
- **Rationale:** Claude Code enforces a timeout on hooks. The hook must launch the work and return quickly.

### C-04: Bash 3.2 compatibility
- **Status:** settled
- **Description:** Shell scripts must work with bash 3.2 (the macOS default).
- **Rationale:** macOS ships bash 3.2 due to GPL licensing. Users shouldn't need to install a newer bash.

### C-05: python3 runtime dependency
- **Status:** settled
- **Description:** python3 must be available on the system. Used for session entrypoint detection in hook scripts, because the JSONL format contains bare newlines in string values that break jq.
- **Rationale:** python3 is standard on macOS and most Linux distributions. The alternative (pure bash/jq parsing) fails on malformed JSON in the transcripts.

## Non-functional Requirements

### NF-01: Reliability — catch-up mechanism
- **Status:** settled
- **Priority:** should
- **Description:** The system must tolerate hook failures (reboots, crashes) without permanent data loss — missed sessions are caught up within a week.
- **Measure:** After a week, >95% of interactive sessions have journal entries (including those backfilled by catch-up).

### NF-02: Safety — no vault corruption
- **Status:** settled
- **Priority:** must
- **Description:** The system must not corrupt or overwrite existing vault files. The journal skill only creates new files, never modifying existing vault content. The reflect skill updates thread and weekly files by overwriting them with new synthesized content.
- **Measure:** No existing file in the vault is modified by the journal skill. Thread and weekly files are updated by the reflect skill only.

### NF-03: Concurrency — throttled catch-up
- **Status:** settled
- **Priority:** should
- **Description:** The catch-up process limits concurrent journal-writing processes to avoid overwhelming the system.
- **Measure:** No more than 3 concurrent journal-writing processes during catch-up.

## Future Scope

- Monthly digests (only weekly is implemented; monthly can be added if weekly proves valuable)
- Dataview queries shipped with the plugin (frontmatter supports Dataview, but no queries are provided)
- Cross-pollination with Claude Code memory (journals and memory serve different audiences — human review vs agent context — kept separate for now)
- RAG or agent consumption of journals (currently human-only; could be made available to agents later)

## Non-Goals

- **Windows support**: Shell scripts, cron, nohup/disown are Unix-native. WSL is untested and unsupported.
- **Journaling subagent/--print sessions**: These are 90%+ of sessions but low-signal for human journaling. Only interactive sessions are journaled.
- **Replacing Claude Code memory**: Journals are for humans. Memory is for agents. They serve different purposes and are not integrated.
- **Exhaustive transcript reproduction**: Journals are summaries with editorial judgment, not full transcripts. The raw JSONL remains available if needed.

## Decisions

### D-01: notesmd CLI for vault writes (optional)
- **Owner:** Nat
- **Decision:** Skills use `notesmd` CLI for vault writes when available, fall back to direct file writes when not. This makes notesmd an optional dependency.
- **Rationale:** notesmd provides a clean API for Obsidian vault operations, but requiring it would limit adoption. Direct file writes work for any markdown folder.
- **Affects:** FR-01, FR-08, FR-10

### D-02: jq for transcript extraction
- **Owner:** LLM
- **Decision:** Transcript extraction uses a jq pipeline to parse the JSONL format.
- **Rationale:** jq is purpose-built for JSON/JSONL processing and widely available.
- **Affects:** FR-14

### D-03: python3 for session entrypoint detection
- **Owner:** LLM
- **Decision:** The hook uses python3 to parse the JSONL and extract the entrypoint field, because the JSONL contains bare newlines in string values that break jq.
- **Rationale:** python3's json module handles malformed JSON more gracefully than jq for this specific parsing task.
- **Affects:** FR-01, FR-12

### D-04: Recursion guard via environment variable
- **Owner:** Nat
- **Decision:** The `AGENT_JOURNAL_SESSION=1` environment variable prevents the journal-writing session from being journaled. Set by the hook; checked by the hook on the next session end. The recursion guard is also set on the digest cron command (install-cron.sh) to prevent the weekly digest session from being journaled.
- **Rationale:** Simple, reliable, no file-based locking needed. --print sessions do fire SessionEnd hooks, so a guard is necessary.
- **Affects:** FR-01

### D-05: find instead of ls glob for JSONL discovery
- **Owner:** LLM
- **Decision:** Use `find | xargs stat | sort` instead of `ls -t ~/.claude/projects/*/*.jsonl` to find the most recent session.
- **Rationale:** The ls glob fails with "argument list too long" at ~14k session files.
- **Affects:** FR-01

### D-06: Narrowed --add-dir scope for background Claude
- **Owner:** Nat
- **Decision:** Background Claude gets `--add-dir ~/.claude/projects --add-dir "$VAULT"` instead of `--add-dir $HOME`.
- **Rationale:** Limits the background process's file access to just what it needs: transcripts and the vault.
- **Affects:** FR-01

### D-07: Transcript extraction inlined in journal skill
- **Owner:** LLM
- **Decision:** The jq pipeline is inlined in the journal SKILL.md rather than depending on the standalone script.
- **Rationale:** Eliminates a runtime dependency on script paths. The standalone script is kept for manual use.
- **Affects:** FR-14

### D-08: Thread decisions are append-only
- **Owner:** Nat
- **Decision:** The Key Decisions section of thread documents grows over time; old decisions are never removed.
- **Rationale:** Decisions are historical record. Removing them loses context about why things are the way they are.
- **Affects:** FR-08

### D-09: Sunday schedule — catch-up at 3am, digest at 5am
- **Owner:** Nat
- **Decision:** Catch-up runs at 3am Sunday, digest at 5am Sunday. Catch-up first so that any backfilled journals are included in the digest.
- **Rationale:** Ordering matters — the digest should reflect a complete week. Early Sunday morning avoids interfering with work.
- **Affects:** FR-11, FR-12

### D-10: Vault folder structure
- **Owner:** Nat
- **Decision:** All output goes under `$VAULT/Agent Journals/` with three subfolders: `Sessions/`, `Threads/`, `Weekly/`.
- **Rationale:** Groups all agent journal output together in the vault. Subfolders separate the three document types.
- **Affects:** FR-01, FR-08, FR-10

### D-11: --dangerously-skip-permissions for background Claude
- **Owner:** Nat
- **Decision:** Background Claude processes (hook and cron) run with `--dangerously-skip-permissions` flag.
- **Rationale:** These are non-interactive background processes that need to read files and write to the vault without human approval of each operation.
- **Affects:** FR-01, FR-11, FR-12

### D-12: Max 3 concurrent catch-up processes
- **Owner:** LLM
- **Decision:** The catch-up script limits to 3 concurrent Claude processes.
- **Rationale:** Each Claude --print process consumes API credits and system resources. Unbounded parallelism could overwhelm both.
- **Affects:** FR-12, NF-03

### D-13: ~~Catch-up skips sessions under 50 lines~~ (Reversed)
- **Owner:** LLM
- **Decision:** ~~The catch-up script skips JSONL files with fewer than 50 lines as a pre-filter before the semantic de minimis check.~~ Removed — the journal skill's semantic de minimis check is the right place for this decision. Short sessions can contain meaningful content (e.g., a critical decision in 30 lines).
- **Rationale:** The blunt line-count filter could skip short-but-meaningful sessions. The skill already has a semantic check; duplicating the filter adds complexity without value.
- **Affects:** FR-12

### D-14: Plugin writes plain markdown; Obsidian is not required
- **Owner:** Nat
- **Decision:** The plugin writes standard markdown files that work with any markdown folder or viewer. Wikilinks and Dataview support are nice-to-haves that work when Obsidian is used, not hard requirements. The "vault" is a plain markdown folder.
- **Rationale:** The core value (structured, searchable session journals) doesn't depend on Obsidian being installed. Requiring Obsidian would unnecessarily limit adoption.
- **Affects:** FR-13, Glossary (Vault)
- **Resolves:** Q-05

### D-15: Debug logging to /tmp
- **Owner:** Nat
- **Decision:** Hook and catch-up scripts write debug logs to /tmp/ (journal-hook-debug.log, journal-catchup.log, agent-journal-last.log, journal-catchup-<prefix>.log). These are the primary debugging mechanism when journals aren't being written.
- **Rationale:** /tmp/ is universally writable, survives the session, and doesn't pollute the vault or the repo. The debug log is the only way to diagnose hook failures.
- **Affects:** FR-01, FR-12

### D-16: Catch-up skips agent-* filenames
- **Owner:** LLM
- **Decision:** The catch-up script skips JSONL files whose basename starts with `agent-` as a fast pre-filter before the entrypoint check. These are subagent transcript files stored in subdirectories.
- **Rationale:** Avoids the cost of running python3 on files that are obviously subagent transcripts.
- **Affects:** FR-12

