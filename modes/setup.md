# Mode: setup

## Invocation

```
/dev-agent setup <url> [url2 url3 ...]
/dev-agent setup --rollback [snapshot-id]
/dev-agent setup --diff <id1> <id2>
```

---

## Rollback / Diff Branch

If `--rollback` flag is present, skip to **Utility: Rollback** at the bottom of this file.

If `--diff` flag is present with two IDs, skip to **Utility: Diff** at the bottom of this file.

---

## Phase 0 — Fetch & Parse Docs

For each URL argument:
- **Confluence URL** (hostname matches known Atlassian domain, path contains `/wiki/spaces/` or `/wiki/x/`): fetch via Atlassian MCP (`getConfluencePage`). Extract page ID from URL path.
- **Generic URL**: fetch via `WebFetch`.

From each document, extract an ordered list of **steps**. A step is any discrete action: installing a tool, running a command, editing a config file, setting an env var, creating a directory, etc. Capture:
- `id` — sequential integer (per-doc, e.g. doc1-step3)
- `description` — human-readable label
- `type` — one of: `shell_command`, `config_edit`, `env_var`, `file_create`, `manual` (requires human action, cannot be automated)
- `command` / `content` — the exact command or content to apply
- `check` — a lightweight command to verify this step is already done (derive from context: e.g. `which brew`, `asdf list ruby | grep 3.3`, `grep "GITHUB_TOKEN" ~/.zshrc`)
- `verify` — post-execution check to confirm success
- `source_doc` — URL this step came from

---

## Phase 1 — Unified Plan

### 1a. Deduplication
Group steps by what they install or configure (not by exact command text). If two steps from different docs do the same thing (e.g., both install `asdf`, both add `GITHUB_TOKEN` to shell rc), merge them into one. Prefer the more complete/specific version. Note which docs the merged step came from.

### 1b. Conflict Detection
Flag conflicts: same tool with different versions (e.g., Ruby 3.1 vs 3.3), same config key with different values, mutually exclusive choices (e.g., Colima vs Rancher Desktop). For each conflict:
- Pause and present the conflict clearly
- Show each option and which doc it came from
- Ask user to choose before proceeding:
  ```
  ⚠️  Conflict detected:
  Doc 1 says: asdf install ruby 3.1
  Doc 2 says: asdf install ruby 3.3
  Which version should be installed? (1/2/custom):
  ```

### 1c. Idempotency Check
For every step that has a `check` command, run it now (before any changes). Mark steps as:
- `✅ already done` — skip during execution, include in report
- `⏳ pending` — will be executed
- `👤 manual` — cannot be automated, will be flagged for user

### 1d. Present Plan
Print the full unified execution plan for user approval:

```
## Setup Plan

Source docs: [list of URLs]

### Steps to Execute
1. [description] (source: doc1)
2. [description] (source: doc1, doc2 — merged)
...

### Already Satisfied (will skip)
- [description]
...

### Manual Steps (cannot be automated — you will need to do these yourself)
- [description]
...

Proceed? (yes / no / edit):
```

- `yes` → continue to Phase 2
- `no` → abort, no changes made
- `edit` → let user remove/reorder steps before proceeding

---

## Phase 2 — Snapshot (Pre-execution State Capture)

Before touching anything, record current machine state for rollback. Save to `~/.claude/setup-snapshots/{ISO8601_TIMESTAMP}.json`.

Snapshot structure:
```json
{
  "id": "{ISO8601_TIMESTAMP}",
  "created_at": "{ISO8601_TIMESTAMP}",
  "source_docs": ["url1", "url2"],
  "brew_packages_before": [],
  "asdf_plugins_before": {},
  "config_files": {
    "~/.zshrc": "<original content>",
    "~/.bashrc": "<original content if exists>",
    "~/.ssh/config": "<original content if exists>",
    "~/.asdfrc": "<original content if exists>",
    "~/.gitconfig": "<original content if exists>"
  },
  "files_created": [],
  "dirs_created": []
}
```

Capture each field:
- `brew_packages_before`: run `brew list --formula` (if brew exists), store as array
- `asdf_plugins_before`: run `asdf plugin list` → for each plugin, run `asdf list <plugin>`, store as `{ "ruby": ["3.3.0"], "nodejs": ["22.9.0"] }`
- `npm_globals_before`: run `npm list -g --depth=0 --json 2>/dev/null | jq '.dependencies | keys'` (if npm exists), store as array of package names
- `pip_packages_before`: run `pip list --format=json 2>/dev/null` (if pip exists), store as array of `{ "name": "...", "version": "..." }` objects
- `config_files`: read each file's current content if it exists; store `null` if not present (new file)
- `files_created` / `dirs_created`: populated during execution, not at snapshot time

Print snapshot path to user:
```
📸 Snapshot saved: ~/.claude/setup-snapshots/{id}.json
   (Run `/dev-agent setup --rollback {id}` to undo all changes)
```

---

## Phase 3 — Execute

Work through the unified plan in order. For each `⏳ pending` step:

1. Print: `▶ [n/total] {description}`
2. Execute based on type:
   - `shell_command` → run via Bash
   - `config_edit` → read file, append/edit the specific line(s), write back. Never overwrite unrelated content.
   - `env_var` → append `export KEY='value'` to the appropriate shell rc file (prefer `~/.zshrc` if using zsh, `~/.bashrc` if using bash). Check if key already exists first — if so, update in place.
   - `file_create` → write the file. If file already exists and content differs, show diff and ask: `overwrite / skip / merge`
   - `manual` → skip execution, print:
     ```
     👤 Manual step required:
        {description}
        {any instructions from doc}
     Press Enter when done (or 's' to skip):
     ```
3. After each step: run its `verify` check. If it fails for a `manual` step:
   ```
   ❌ Verification failed for manual step: {description}
   Options: [r]etry verification / [s]kip and continue / [d]one — mark as complete anyway
   ```
   - `retry` → re-run the verify check (user may have just finished the manual step)
   - `skip` → mark as skipped, continue to next step
   - `done` → mark as complete without verification (user asserts it's done), continue

   If it fails for a non-manual step:
   ```
   ❌ Step failed: {description}
   Error: {error output}
   Options: [r]etry / [s]kip / [a]bort
   ```
   - `retry` → re-run the same step
   - `skip` → mark as skipped, continue to next step
   - `abort` → stop execution. Offer rollback:
     ```
     Execution aborted at step {n}. Run `/dev-agent setup --rollback {snapshot_id}` to undo completed steps.
     ```
4. Track newly created files/dirs and append to snapshot's `files_created` / `dirs_created` lists (update the snapshot file in place after each creation).

Print a live progress line after each step:
```
✅ [1/12] Homebrew — already installed, skipped
✅ [2/12] asdf — installed
✅ [3/12] Ruby 3.3.0 — installed via asdf
⏩ [4/12] GITHUB_TOKEN — added to ~/.zshrc
```

---

## Phase 4 — Verify

### 4a. Doc-specified Checks
Run any verification commands mentioned explicitly in the source docs (e.g., `ssh -T git@github.com`, `aws sts get-caller-identity`, `docker ps`, `brew --version`, `asdf --version`).

### 4b. Own Sanity Checks
For every tool installed during this session, run its existence/version check:
- Brew: `brew --version`
- asdf: `asdf --version`
- Ruby: `ruby --version`
- Go: `go version`
- Node.js: `node --version`
- Yarn: `yarn --version`
- AWS CLI: `aws --version`
- saml2aws: `saml2aws --version`
- Docker: `docker --version`
- Colima: `colima --version` (if installed)

### 4c. Report

```
## Setup Report

Source docs: [list]
Snapshot ID: {id} (rollback available)

### Execution Summary
✅ Completed  — {n} steps
⏩ Skipped    — {n} steps (already satisfied)
👤 Manual     — {n} steps (require human action)
❌ Failed     — {n} steps

### Verification
✅ brew 4.x.x
✅ asdf 0.x.x
✅ ruby 3.x.x (via asdf)
❌ aws sts get-caller-identity — not authenticated (run: saml2aws login --skip-prompt --force)
...

### Manual Steps Remaining
1. {description + instructions}
...

### Rollback
To undo all changes made in this session:
  /dev-agent setup --rollback {snapshot_id}
```

---

## Utility: Rollback

### List Snapshots (no snapshot-id given)
Read `~/.claude/setup-snapshots/` directory. List all snapshots sorted by date descending:
```
Available setup snapshots:
  1. 2026-04-07T10:30:00Z  (2 docs, 12 steps)
  2. 2026-04-06T15:00:00Z  (1 doc, 8 steps)

Which snapshot to roll back? (1/2 or full ID):
```

### Rollback Execution
Load the snapshot JSON. Confirm with user:
```
⚠️  Rolling back snapshot {id}
    This will:
    - Restore {n} config files to their previous content
    - Uninstall {n} Homebrew packages added during this session
    - Remove {n} asdf plugins/versions added during this session
    - Delete {n} files/directories created during this session

    What CANNOT be undone automatically:
    - Manual steps you performed yourself
    - sudo-level installs (AWS session manager, etc.) — listed below for manual removal
    - External auth/account changes (GitHub PAT, AWS SSO)

Proceed with rollback? (yes/no):
```

Steps:
1. **Restore config files** — for each key in `config_files`: if original was `null` (file didn't exist), delete it. Otherwise write back the original content.
2. **Uninstall Homebrew packages** — compute diff: `current brew list` minus `brew_packages_before`. Run `brew uninstall {package}` for each.
3. **Remove asdf plugins/versions** — compute diff against `asdf_plugins_before`. Remove added versions via `asdf uninstall {plugin} {version}`. If all versions of a plugin were added, remove the plugin via `asdf plugin remove {plugin}`.
3a. **Remove npm globals** — compute diff: `current npm list -g --depth=0` names minus `npm_globals_before`. Run `npm uninstall -g {package}` for each added package (skip if npm not present).
3b. **Remove pip packages** — compute diff: `current pip list` names minus `pip_packages_before` names. Run `pip uninstall -y {package}` for each added package (skip if pip not present).
4. **Delete created files/dirs** — for each path in `files_created`: delete if exists. For each path in `dirs_created`: `rmdir` if empty (do not force-delete non-empty dirs — warn user instead).
5. **List manual removals** — print anything that cannot be auto-undone:
   ```
   ⚠️  The following require manual removal:
   - /usr/local/bin/session-manager-plugin (installed via sudo)
   - /usr/local/sessionmanagerplugin/ (directory)
   ```

Print rollback summary:
```
## Rollback Complete

✅ Config files restored: {n}
✅ Brew packages removed: {n}
✅ asdf plugins/versions removed: {n}
✅ npm globals removed: {n}
✅ pip packages removed: {n}
✅ Files deleted: {n}
⚠️  Manual removals needed: {n} (see above)

Snapshot {id} has been archived to ~/.claude/setup-snapshots/rolled-back/{id}.json
```

Move (don't delete) the snapshot file to `~/.claude/setup-snapshots/rolled-back/` after successful rollback, so it can be referenced but won't appear in the active list.

---

## Utility: Diff

### Usage
```
/dev-agent setup --diff <id1> <id2>
```

Compares two snapshots side by side. Load both JSONs from `~/.claude/setup-snapshots/`. If either is not found, check `~/.claude/setup-snapshots/rolled-back/` before erroring.

Produce a diff report:

```
## Snapshot Diff — {id1} vs {id2}

| Field | {id1} ({date1}) | {id2} ({date2}) |
|-------|-----------------|-----------------|
| Source docs | doc1.url | doc2.url |
| Steps executed | 12 | 9 |
| Steps skipped | 3 | 5 |

### Brew packages
  Added in {id2} but not {id1}: [list]
  Added in {id1} but not {id2}: [list]
  Common to both: [list]

### asdf plugins/versions
  Added in {id2} but not {id1}: [list]
  Added in {id1} but not {id2}: [list]

### npm globals
  Added in {id2} but not {id1}: [list]
  Added in {id1} but not {id2}: [list]

### pip packages
  Added in {id2} but not {id1}: [list]
  Added in {id1} but not {id2}: [list]

### Config file changes
  {file}: changed in {id2} only / changed in both / unchanged
```
