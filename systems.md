# External Systems

## Claude Code CLI
- **What it is:** The Claude Code command-line interface — both the runtime that hosts the plugin and the tool used to spawn background journal-writing processes.
- **Server/hostname:** Local CLI binary (typically `~/.claude/local/claude` or on `$PATH`)
- **Access method:** CLI invocation (`claude --print -p "..."`)
- **Auth model:** Uses the user's existing Claude Code authentication (Anthropic API key or OAuth session)
- **Credential location:** Managed by Claude Code itself (`~/.claude/`)
- **Used for:** (1) Hosting the plugin (skills, hooks). (2) Spawning background `--print` processes that run the journal skill to write entries. (3) Spawning background processes for scheduled weekly digests.
- **Gotchas:**
  - `--print` sessions DO fire SessionEnd hooks, so a recursion guard is necessary to prevent infinite journaling loops.
  - The background process needs `--dangerously-skip-permissions` because there's no human to approve file operations.
  - Each background `claude --print` invocation consumes API credits.

## Claude Code Session Transcripts
- **What it is:** JSONL files recording every message in a Claude Code session — stored by Claude Code itself, not by this plugin.
- **Server/hostname:** Local filesystem at `~/.claude/projects/`
- **Access method:** File read (JSONL format, one JSON object per line)
- **Auth model:** Local filesystem permissions
- **Credential location:** N/A
- **Used for:** Reading the raw session data to write journal entries. The hook finds the most recently modified JSONL; the journal skill extracts readable conversation from it.
- **Gotchas:**
  - Files are organized as `~/.claude/projects/<encoded-project-path>/<session-id>.jsonl`
  - At scale (~14k+ files), the `ls` glob `~/.claude/projects/*/*.jsonl` fails with "argument list too long" — `find` must be used instead.
  - The JSONL can contain bare newlines within JSON string values, which breaks some jq invocations. Python's json module handles this more reliably for specific fields (entrypoint detection).
  - The `entrypoint` field on the first `attachment`-type record distinguishes interactive sessions (`cli`, `claude-desktop`) from subagents (`sdk-cli`) and `--print` invocations.

## Obsidian Vault
- **What it is:** A folder of markdown files managed by the Obsidian note-taking application. This is where all journal output is written.
- **Server/hostname:** Local filesystem, path configured via `OBSIDIAN_VAULT` environment variable (default: `~/obsidian`)
- **Access method:** File write (markdown files with YAML frontmatter)
- **Auth model:** Local filesystem permissions
- **Credential location:** N/A
- **Used for:** Storing session journals, thread documents, and weekly digests. All output goes under `$VAULT/Agent Journals/` with subfolders `Sessions/`, `Threads/`, `Weekly/`.
- **Gotchas:**
  - The vault path varies by user. The `OBSIDIAN_VAULT` env var must be set in `~/.claude/settings.json` under `env` for the hook and cron jobs to find it.
  - If the vault is on iCloud (common for macOS Obsidian users), the actual path may be something like `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/VaultName` — users typically symlink this to a shorter path.
  - The `Agent Journals/` folder (with space) and its three subfolders must be created before first use.

## notesmd CLI (optional)
- **What it is:** A command-line tool for reading and writing to an Obsidian vault with frontmatter support.
- **Server/hostname:** Local CLI binary (user-installed, typically at `~/bin/notesmd`)
- **Access method:** CLI invocation (`notesmd create`, `notesmd print`, `notesmd search-content`)
- **Auth model:** N/A (local filesystem tool)
- **Credential location:** N/A
- **Used for:** Writing journal entries, thread documents, and weekly digests to the vault. Provides a cleaner API than raw file writes.
- **Gotchas:**
  - This is optional. If notesmd is not installed, the plugin falls back to direct file writes.
  - notesmd has its own default vault configuration — make sure it points to the same vault as `OBSIDIAN_VAULT`.

## cron (system)
- **What it is:** The Unix cron scheduler for periodic background jobs.
- **Server/hostname:** Local system cron daemon
- **Access method:** `crontab` command
- **Auth model:** User-level crontab (no root required)
- **Credential location:** N/A
- **Used for:** (1) Weekly catch-up of missed journals (Sunday 3am). (2) Weekly digest generation (Sunday 5am).
- **Gotchas:**
  - Cron jobs run in a minimal shell environment — `$PATH`, `$HOME`, and env vars like `OBSIDIAN_VAULT` may not be set. The install script uses absolute paths to scripts.
  - The `install-cron.sh` script is safe to run multiple times — it removes existing vaultbot entries before adding new ones.
  - On macOS, cron requires Full Disk Access permission in System Settings to access files outside the user's home directory.
