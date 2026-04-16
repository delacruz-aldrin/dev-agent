# setup

Reads setup documentation, deduplicates steps, snapshots your machine state, runs the setup, verifies everything worked — and can fully roll back if anything goes wrong.

## When to use

- Setting up a project for the first time on a new machine
- Onboarding a new team member
- Following a new dev setup doc that was just updated
- After running setup before and wanting to compare two configurations

## Usage

```
/dev-agent setup <url> [url2 url3 ...]
/dev-agent setup --rollback [snapshot-id]
/dev-agent setup --diff <id1> <id2>
```

Accepts any combination of URLs — Confluence pages, Jira pages, or any public web URL:

```
/dev-agent setup https://your-org.atlassian.net/wiki/spaces/ENG/pages/123/Dev+Setup
/dev-agent setup https://your-org.atlassian.net/wiki/spaces/ENG/pages/123 https://another.atlassian.net/wiki/spaces/BE/pages/456
```

## What it does

### Step 1 — Read and parse docs

Fetches each URL and extracts every discrete step:
- Installing a tool
- Running a command
- Editing a config file
- Setting an environment variable
- Creating a directory

Each step gets a type (`shell_command`, `config_edit`, `env_var`, `file_create`, or `manual`) and a verification check.

### Step 2 — Build a unified plan

When you pass multiple URLs, setup deduplicates across them — if two docs both say "install asdf", it's only done once.

**Conflict detection:** if two docs specify the same tool at different versions (e.g., Ruby 3.1 vs 3.3), setup pauses:

```
⚠️ Conflict detected:
Doc 1 says: asdf install ruby 3.1
Doc 2 says: asdf install ruby 3.3
Which version should be installed? (1/2/custom):
```

**Idempotency check:** for every step with a check command, setup runs it first. Steps that are already satisfied are marked `✅ already done` and skipped — only `⏳ pending` steps are executed.

### Step 3 — Show plan for approval

Before running anything, setup presents the full execution plan:

```
## Setup Plan

Source docs: [list of URLs]

### Steps to Execute
1. Install Homebrew (source: doc1)
2. Install asdf (source: doc1, doc2 — merged)
3. Install Ruby 3.3.0 via asdf (source: doc2)

### Already Satisfied (will skip)
- Homebrew — already installed

### Manual Steps (cannot be automated — you will need to do these yourself)
- Add GITHUB_TOKEN to 1Password

Proceed? (yes / no / edit)
```

You can also choose `edit` to remove or reorder steps before proceeding.

### Step 4 — Snapshot

Before touching anything, setup saves your current machine state to `~/.claude/setup-snapshots/`. This is what makes rollback possible. The snapshot captures:
- All currently installed Homebrew packages
- All asdf plugins and versions
- npm global packages
- pip packages
- Content of key config files (`~/.zshrc`, `~/.bashrc`, `~/.gitconfig`, `~/.ssh/config`, etc.)

```
📸 Snapshot saved: ~/.claude/setup-snapshots/2026-04-16T10:30:00Z.json
   (Run `/dev-agent setup --rollback 2026-04-16T10:30:00Z` to undo all changes)
```

### Step 5 — Execute

Runs each pending step in order, with live progress:

```
✅ [1/12] Homebrew — already installed, skipped
✅ [2/12] asdf — installed
✅ [3/12] Ruby 3.3.0 — installed via asdf
⏩ [4/12] GITHUB_TOKEN — added to ~/.zshrc
```

If a step fails, you choose: `retry` / `skip` / `abort`. Aborting offers to run the rollback immediately.

Manual steps (e.g., "paste your API key into 1Password") are flagged and paused for you to complete — with a verification check you can retry after finishing.

### Step 6 — Verify

Runs verification checks for every tool installed during the session (`brew --version`, `ruby --version`, `node --version`, etc.) plus any explicit checks from the source docs.

## Rollback

Undoes everything setup changed in a previous session:

```
/dev-agent setup --rollback                     ← lists available snapshots, asks which to roll back
/dev-agent setup --rollback 2026-04-16T10:30:00Z
```

Rollback restores:
- Config files to their previous content (or deletes them if they didn't exist before)
- Homebrew packages to the pre-setup list (uninstalls anything added)
- asdf plugins and versions added during setup
- npm global packages added during setup
- pip packages added during setup
- Deletes files and directories created during setup

Things rollback **cannot** undo automatically (listed explicitly for you to do manually):
- `sudo`-level installs
- External auth changes (GitHub PAT, AWS SSO, etc.)
- Manual steps you completed yourself

After rollback, the snapshot is archived (moved to `rolled-back/`) so it doesn't appear in the active list but can still be referenced.

## Diff — compare two setups

```
/dev-agent setup --diff <id1> <id2>
```

Shows what changed between two setup sessions:

```
## Snapshot Diff — 2026-04-10 vs 2026-04-16

### Brew packages
  Added in Apr 16 but not Apr 10: postgresql@16, redis
  Added in Apr 10 but not Apr 16: mysql

### asdf plugins/versions
  Added in Apr 16 but not Apr 10: ruby 3.3.5

### Config file changes
  ~/.zshrc: changed in Apr 16 only
  ~/.gitconfig: unchanged
```

Useful for comparing a teammate's setup against your own, or auditing what a re-run added.

## What you'll see (final report)

```
## Setup Report

Source docs: [list]
Snapshot ID: 2026-04-16T10:30:00Z (rollback available)

### Execution Summary
✅ Completed  — 9 steps
⏩ Skipped    — 3 steps (already satisfied)
👤 Manual     — 2 steps (require human action)
❌ Failed     — 0 steps

### Verification
✅ brew 4.x.x
✅ asdf 0.x.x
✅ ruby 3.3.0 (via asdf)
✅ node 22.x.x (via asdf)
❌ aws sts get-caller-identity — not authenticated (run: saml2aws login)

### Manual Steps Remaining
1. Add GITHUB_TOKEN to ~/.zshrc (instructions: ...)
2. Configure 1Password CLI with your personal vault

### Rollback
To undo all changes: /dev-agent setup --rollback 2026-04-16T10:30:00Z
```

## Guardrails

- **Nothing runs until you approve the plan** — always shown first
- **Snapshot taken before any changes** — rollback is always available
- **Idempotency check** — steps already done are skipped; running setup twice is safe
- **Conflict detection** — version mismatches across docs are surfaced before execution, not mid-way
- **Step-level error recovery** — each failure is handled individually (retry/skip/abort); setup never silently continues past an error
