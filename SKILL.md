---
name: dev-agent
description: Twelve-mode dev agent + config utility. Modes: audit (codebase assessment), fix (bug diagnosis+fix), refix (re-diagnose and fix a rejected/reverted deployment), build (generate endpoints), verify (PR root cause check), sweep (autonomous Jira→PR pipeline), respond (address PR comments), review (review colleague PRs), follow-up (Slack nudge for PR review), setup (follow setup docs and configure local environment with rollback support), pr (open a PR for the current branch), refactor (restructure code without changing behavior — accepts file, line range, description, IDE selection, or audit finding). Use "dev-agent config" to view, edit, or reset project config. Always reads settings from .claude/dev-agent.json.
---

# Dev-Agent

## Mode Routing

On invocation, read the corresponding file from `~/.claude/skills/dev-agent/modes/` then execute it. All modes use the shared systems below.

| Invocation | File |
|---|---|
| `/dev-agent audit` | `modes/audit.md` |
| `/dev-agent fix` | `modes/fix.md` |
| `/dev-agent refix` | `modes/refix.md` |
| `/dev-agent build` | `modes/build.md` |
| `/dev-agent sweep` | `modes/sweep.md` |
| `/dev-agent verify` | `modes/verify.md` |
| `/dev-agent respond` | `modes/respond.md` |
| `/dev-agent review` | `modes/review.md` |
| `/dev-agent follow-up` | `modes/follow-up.md` |
| `/dev-agent setup <url> [url2 ...]` | `modes/setup.md` |
| `/dev-agent setup --rollback [id]` | `modes/setup.md` |
| `/dev-agent pr [ticket key or URL]` | `modes/pr.md` |
| `/dev-agent refactor` | `modes/refactor.md` |
| `/dev-agent refactor <file>` | `modes/refactor.md` |
| `/dev-agent refactor <file>:<start>-<end>` | `modes/refactor.md` |
| `/dev-agent refactor "<description>"` | `modes/refactor.md` |
| `/dev-agent refactor --from-audit <n>` | `modes/refactor.md` |
| `/dev-agent config` | See **Utility: Config** below |

---

## Mode Chains

Natural workflows across modes — use these as a guide for what to run next:

| Situation | Mode sequence |
|---|---|
| New ticket assigned | `fix` or `build` → PR auto-created |
| PR gets review comments | `respond` → re-requests review, polls CI |
| PR gets rejected / reverted | `refix` → new branch, corrected fix, new PR |
| Unsure a fix is correct before merging | `verify` → read-only analysis; add `--comment` to post findings as a GitHub review |
| Reviewer needs a nudge | `follow-up` → posts to existing Slack thread |
| Batch of tickets (end-of-sprint) | `sweep` → processes all assigned tickets sequentially |
| Code smells / tech debt found | `audit` → surfaces risks, optionally files Jira tickets |
| Audit finding needs structural cleanup | `audit` → `refactor --from-audit <n>` → PR |
| Inline refactor request (file, lines, or selection) | `refactor <target>` → PR |
| Review a colleague's PR | `review` → inline comments + verdict + Slack mention |
| Manual code work done, need a PR | `pr` → opens PR for current branch |
| New machine / environment setup | `setup <url>` → follows docs, snapshots state, supports rollback |

---

## Shared: Config System

### Config File
`.claude/dev-agent.json` in project root. Committed to repo — shared across teammates.

```json
{
  "version": 1,
  "repo": "owner/repo",
  "jira_domain": "your-org.atlassian.net",
  "jira_project": "MULTI,HQA",
  "slack_channel": "team-dev-agent",
  "slack_group": "likha-dev-agent-eng",
  "pr_reviewer_team": "dev-agent",
  "pr_milestone": "Untracked",
  "base_branch": "main"
}
```

### Known Config Keys
The canonical key list (used for missing-key detection and validation):

| Key | Format | Example |
|---|---|---|
| `version` | integer — managed automatically, never prompt the user for this | `1` |
| `repo` | `owner/repo` — must contain exactly one `/` | `C-FO/baberu` |
| `jira_domain` | hostname only, no protocol | `your-org.atlassian.net` |
| `jira_project` | one or more uppercase alphanumeric keys, comma-separated (spaces around commas are accepted and stripped on save) | `MULTI` or `MULTI, HQA` |
| `slack_channel` | no `#` prefix | `team-dev-agent` |
| `slack_group` | handle, no `@` | `likha-dev-agent-eng` |
| `pr_reviewer_team` | GitHub team slug | `dev-agent` |
| `pr_milestone` | exact milestone name | `Untracked` |
| `base_branch` | exact branch name to open PRs against | `main` |

### JQL Project Expansion
Whenever a mode builds a JQL query using `{jira_project}`, always expand it first:
- Parse `jira_project` by splitting on `,` and trimming whitespace → `JIRA_PROJECTS` array
- Single entry → use `project = KEY`
- Multiple entries → use `project in (KEY1, KEY2)`

Never interpolate `{jira_project}` raw into JQL.

### Config Version & Migration

The current schema version is **1**. The `version` field is managed automatically — never prompt the user for it.

**Version detection:** when reading `.claude/dev-agent.json`:
- `version` field missing → treat as version **0** (pre-versioning)
- `version` present → use its value

**Migration table** — run each migration in order from the detected version up to current:

| From → To | What changes |
|---|---|
| 0 → 1 | No data changes. Write `"version": 1` to the file. |

After running any migration, write the updated file before proceeding. Migrations are additive and backward-compatible — existing values are never overwritten.

### First Run Detection
At Phase 0 of every mode: read `.claude/dev-agent.json` if it exists.
1. If file missing entirely → run **Config Setup** (all non-`version` keys), then write file with `"version": 1`
2. If file exists → run migrations if `version < 1` (see migration table above)
3. Diff remaining keys (excluding `version`) against the Known Config Keys list:
   - Some keys missing → run **Config Setup** for missing keys only, preserve existing values
   - All keys present → proceed

### Config Setup
Show which keys need values (all for first run, or only the missing ones for partial configs). For each missing key, show the expected format and an example, then prompt one at a time:
```
👋 dev-agent needs a few values for this project:

[key name] ([format hint], e.g. [example]):
```
After all values are collected, validate each:
- `repo`: must match `[^/]+/[^/]+` (exactly one `/`)
- `jira_domain`: must not contain `://` or spaces
- `jira_project`: split on `,`, trim whitespace from each token — each token must be uppercase letters and digits only. Normalize before writing: re-join tokens with `,` (no spaces), so `"MULTI, HQA"` is stored as `"MULTI,HQA"`.
- `slack_channel`, `slack_group`, `pr_reviewer_team`, `pr_milestone`: must be non-empty strings
- `base_branch`: run `git ls-remote --heads origin {value}` — if output is empty, the branch doesn't exist on the remote. Re-prompt: "Branch '{value}' not found on remote. Check the branch name and try again."

If any validation fails: show the specific error and re-prompt that field only. Do not re-ask fields that passed.

Write `.claude/dev-agent.json` (merge with any existing valid keys — do not overwrite values that weren't re-prompted).

Offer to commit:
```
✅ Config saved. Commit it so teammates share the setup — shall I run:
  git add .claude/dev-agent.json && git commit -m "chore: add dev-agent config"
Reply 'yes' to commit or 'no' to skip.
```
If yes: run the commit. If no: remind them to commit manually. Then proceed with the originally invoked mode.

### Config Usage
Every mode reads all values from `.claude/dev-agent.json`. Never hardcode or infer. Store `repo` as `REPO`. Use `jira_domain` as `cloudId` for all Atlassian MCP calls.

---

## Shared: Backend Detection

Run once at Phase 0 of any mode that touches the backend (audit, fix, build, sweep). Store results as session variables.

### Step 1 — Detect Framework (`BE_FRAMEWORK`)
Check in order:
- `Gemfile` contains `rails` → `BE_FRAMEWORK=rails`
- Root `package.json` + `"express"` in dependencies → `BE_FRAMEWORK=express`
- `requirements.txt` or `pyproject.toml` contains `django` → `BE_FRAMEWORK=django`
- `requirements.txt` or `pyproject.toml` contains `fastapi` → `BE_FRAMEWORK=fastapi`
- `go.mod` exists → `BE_FRAMEWORK=go`
- None → `BE_FRAMEWORK=none` — skip all backend steps, note in report

### Step 2 — Resolve Commands

| Variable | rails | express | django/fastapi | go |
|---|---|---|---|---|
| `BE_TEST_CMD` | `bundle exec rspec` | from `package.json` `scripts.test` | `pytest` | `go test ./...` |
| `BE_LINT_FIX` | `bundle exec rubocop -a` | same as `FE_LINT_FIX` | `ruff check --fix` | `gofmt -w .` |
| `BE_LINT_CHECK` | `bundle exec rubocop` | same as `FE_LINT_CHECK` | `ruff check` | `go vet ./...` |
| `BE_FORMAT_CMD` | `bundle exec stree write` | none | none | none |

### Step 3 — Resolve Architecture Trace (`BE_ARCH_TRACE`)

| `BE_FRAMEWORK` | Trace path |
|---|---|
| `rails` | `config/routes.rb` → Controller → Usecase → Interactor → Model |
| `express` | `routes/` → controller/handler → service → model |
| `django` | `urls.py` → views → serializers → models |
| `fastapi` | `routers/` → endpoints → services → models |
| `go` | router → handler → service → repository |

---

## Shared: Frontend Detection

Run once at Phase 0 of any mode that touches frontend (audit, fix, build, sweep). Store results as session variables.

### Step 1 — Locate Frontend Root (`FRONTEND_ROOT`)
Check in order: `front/`, `frontend/`, `app/frontend/`, `client/`, `src/` — use first directory containing a `package.json`. If none: `FRONTEND_ROOT=none`. If `BE_FRAMEWORK=none` and a root `package.json` exists, use project root as `FRONTEND_ROOT`.

### Step 2 — Detect Stack from `{FRONTEND_ROOT}/package.json`

**`STORE`:** `@tanstack/react-query` or `@tanstack/query-core` → `tanstack-query` | `@reduxjs/toolkit` or `react-redux` → `redux` | `zustand` → `zustand` | else → `none`

**`API_CLIENT`:** `orval` in devDeps → `orval` | `@hey-api/openapi-ts` → `hey-api` | else → `manual`

**`FE_TEST`:** `vitest` → `vitest` (cmd: `yarn test`) | `jest` or `@jest/core` → `jest` (cmd: `yarn test`) | else → `none`

**`FE_LINT`:** `@biomejs/biome` → `biome` (fix: `yarn lint:fix`, check: `yarn lint`) | `eslint` → `eslint` (fix: `yarn lint --fix`, check: `yarn lint`) | else → `none`

**`API_GEN_CMD`:** If `API_CLIENT=orval`: check Makefile and `package.json` scripts for `generate-client` or `generate-all`. Store first match.

---

## Shared: Frontend Convention Sampling

### When to Sample
Sample in **build** and **fix** whenever: new API endpoint added, data shape changed, new user-facing feature, existing API response modified. Skip if purely internal (no UI surface). Skip if `FRONTEND_ROOT=none`.

### How to Sample (always)
- Closest existing TS interface file — naming, nullable vs optional fields
- Closest existing component for the feature area — props, hook usage, routing
- Any existing frontend tests — library, async patterns, mocking

### Conditional on `STORE`
- `tanstack-query` + `API_CLIENT=orval`: closest orval-generated hook + MSW mock handler
- `tanstack-query` + other: closest `useQuery`/`useMutation`
- `redux`: closest Redux slice + service file
- `zustand`: closest store file + selector pattern
- `none`: closest `useState`/`useReducer` + fetch/axios

Never invent new patterns or introduce new libraries.

---

## Shared: Create Branch

Used in fix, build, sweep before any code changes.

### Branch Naming
Derive from ticket type and key:
- Bug → `bug/{TICKET-KEY}` (e.g. `bug/HQA-12345`)
- Story/Task/Improvement/Sub-task → `feat/{TICKET-KEY}` (e.g. `feat/MULTI-456`)
- No ticket (manual input) → `fix/manual-{short-slug}` or `feat/manual-{short-slug}`

### Steps
Check for branch collision first:
```bash
git branch --list "{branch-name}"
```
If the branch already exists, append `-2`, then `-3`, etc. until a free name is found.

```bash
git checkout -b {branch-name}
```

---

## Shared: Run Quality Checks

Used in fix, build, respond. Run after all code changes.

1. If `BE_FRAMEWORK≠none`:
   - Run `{BE_LINT_FIX}` → re-run `{BE_LINT_CHECK}` to confirm clean
     - Still failing → manually fix remaining offenses → re-run
     - Still failing → revert all changes, note in report, stop
   - If `BE_FORMAT_CMD≠none`: run `{BE_FORMAT_CMD}` → re-run to confirm clean
     - Still failing → manually fix → re-run
     - Still failing → revert all changes, note in report, stop
2. If `FE_LINT≠none`: run `{FE_LINT_FIX}` → then `{FE_LINT_CHECK}` to confirm clean

---

## Shared: Create PR

Used in fix, build, refix, pr. Creates a PR for the current branch using the project's PR template.

### Step 1 — Read PR Template
Check for a PR template in order:
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/PULL_REQUEST_TEMPLATE`
- `.github/pull_request_template.md`

If found: read it and use its exact section structure. If not found: use this default:
```
## Summary

## Test Cases
- [ ]

## Out of Scope
```

### Step 2 — Fill Template
Infer values from commits and diff:
- **Tickets** — include if passed in (e.g. Jira link from the invoking mode). Leave blank if none.
- **Summary** — what changed and why, inferred from commits + diff.
- **Out of Scope** — what was intentionally not changed.
- **Test Cases** — checklist (`- [ ]`) of steps a reviewer can follow to verify.
- **AI Prompt** — include if the section exists in the template.

### Step 3 — Create PR
Push branch if not already pushed:
```bash
git push -u origin HEAD
```

Create via REST API:
```bash
gh api repos/{REPO}/pulls -X POST \
  -f title="<title>" \
  -f head="<branch>" \
  -f base="{base_branch}" \
  -f body="<filled template>" \
  --jq '.number, .html_url'
```

Store PR number as `PR_NUMBER`, URL as `PR_URL`.

### Step 4 — Apply Metadata
**Labels** — always apply `ai-contribution-level:3` plus one productivity label:

| Change type | Label |
|---|---|
| New feature or user-facing functionality | `1.Feature development` |
| Bug fix, dependency update, maintenance | `2.Bugfix & Maintenance` |
| Infrastructure, platform work | `3.Tech investment` |
| Tests, refactoring, code quality | `4.Quality improvement` |
| Everything else (deploys, tooling, config) | `5.Others` |

```bash
gh api repos/{REPO}/issues/{PR_NUMBER}/labels -X POST \
  -f "labels[]=<productivity-label>" \
  -f "labels[]=ai-contribution-level:3"
```

**Reviewer team:**
```bash
gh api repos/{REPO}/pulls/{PR_NUMBER}/requested_reviewers -X POST --input - <<'EOF'
{"team_reviewers": ["{pr_reviewer_team}"]}
EOF
```

**Milestone** — look up ID then set:
```bash
MILESTONE_ID=$(gh api repos/{REPO}/milestones --jq '.[] | select(.title=="{pr_milestone}") | .number')
gh api repos/{REPO}/issues/{PR_NUMBER} -X PATCH --input - <<EOF
{"milestone": $MILESTONE_ID}
EOF
```

If any metadata step fails: note in report and continue — do not abort.

---

## Shared: Post Slack Thread

Used in fix, build, sweep. If Slack MCP fails: note in report and continue.

1. Look up `{slack_group}` group ID via Slack MCP (once per session — reuse across tickets in sweep)
2. Post parent to `#{slack_channel}`:
   ```
   ✅ [TICKET] Summary
   PR: https://github.com/{REPO}/pull/{pr_number}
   ```
3. Reply in thread: warm, humorous, 2–4 sentences. Mention `<!subteam^GROUP_ID>`. Each ticket in a sweep must use a different angle. Never: "just following up", "circling back", "As an AI".

---

## Shared: Session State

At the end of Phase 0 in every mode that runs Backend or Frontend Detection, print a Session State block before proceeding. This surfaces what was resolved so the user can catch misdetections early. Only include variables resolved in this mode's Phase 0. Omit variables that don't apply. Use `none` for variables explicitly resolved to none (e.g. `FRONTEND_ROOT=none`).

---

## Shared: Session Context

Persists findings across mode runs for the same ticket so modes can skip redundant re-detection and hand off results directly.

### Context File Location
`.claude/dev-agent/context/{TICKET_KEY}.json`
- Keyed by ticket key (e.g. `HQA-123`) or branch slug for manual inputs (e.g. `manual-page-list-column-widths`)
- Stored in `.claude/` — gitignored, local only, never committed

### Schema
```json
{
  "ticket": "HQA-123",
  "stack": {
    "be_framework": "rails",
    "frontend_root": "front/",
    "store": "tanstack-query",
    "api_client": "orval",
    "detected_at": "<ISO8601>",
    "lockfile_mtime": "<epoch ms of Gemfile / package.json / go.mod at detection time>"
  },
  "fix": {
    "timestamp": "<ISO8601>",
    "head_sha": "<git SHA after commit>",
    "branch": "fix/HQA-123",
    "root_cause": "<one-line summary>",
    "files_changed": ["path/to/file.rb"],
    "callers_checked": ["path/to/caller.rb"],
    "side_effects": ["<file:method — one-line impact summary>"],
    "pr_number": 519,
    "pr_url": "https://github.com/owner/repo/pull/519"
  },
  "verify": {
    "timestamp": "<ISO8601>",
    "pr_number": 519,
    "verdict": "NEEDS_DISCUSSION",
    "blocking_findings": ["<finding text>"]
  },
  "refix_count": 0
}
```

### Read Rules (Phase 0)
Check for `.claude/dev-agent/context/{TICKET_KEY}.json` at the start of Phase 0:
- If missing: proceed with full detection as normal
- If present: print `[context] loaded HQA-123 (fix ran <N>m ago)` in the Session State block

**Stack reuse:** use cached `stack` values and skip Backend/Frontend Detection only if `stack.lockfile_mtime` matches the current mtime of the relevant lockfile (Gemfile for rails, `{FRONTEND_ROOT}/package.json` for FE, `go.mod` for go). If mismatched: re-detect and overwrite cached values. Print `[context] stack reused from cache` or `[context] stack re-detected (lockfile changed)` accordingly.

**Fix summary (verify):** use `fix` data as a trace hint only if `fix.branch` matches the PR's head branch.

**Verify findings (refix):** use `verify` data as the rejection basis only if `verify.pr_number` matches the rejected PR number passed as the argument.

### Write Rules
Each mode merges its key into the context file — never replaces the entire file. Read first, update the relevant key, write back.

| Mode | Writes |
|---|---|
| `fix` | `stack` (if re-detected), `fix` (root_cause, files_changed, callers_checked, side_effects, pr_number, pr_url, head_sha, timestamp, branch) |
| `verify` | `verify` (verdict, blocking_findings, pr_number, timestamp) |
| `refix` | increments `refix_count`; clears `fix` and `verify` keys |

Write at the **end** of the mode, after all work is done. If the write fails: note in report and continue — never block on context writes.

---

## Shared: Analysis Frame

Mode files contain `<analysis>` blocks in their Phase 1 sections. These are **internal reasoning scaffolds — never output them literally**. Use the structure to frame your thinking, then produce only the result described in the Report or Execute section that follows.

```xml
<!-- Example — do not output this block, use it to reason -->
<analysis>
  <context>...</context>
  <files>...</files>
  <task>...</task>
  <constraints>...</constraints>
</analysis>
```

---

## Utility: dev-agent config

```
/dev-agent config            ← show current config
/dev-agent config edit       ← update specific values interactively
/dev-agent config reset      ← wipe and redo setup
/dev-agent config validate   ← test connectivity for all configured integrations
```

**Show:** Display all key-value pairs from `.claude/dev-agent.json` in a table. If missing: "No config found. Run any dev-agent mode to trigger setup."

**Edit:** Display the full key list with current values and their expected formats (from Known Config Keys table). Ask the user which keys to update by name or number. For each selected key: show current value → prompt for new → validate format → write. Offer to commit after saving (same commit offer as Config Setup).

**Reset:** Confirm first: "⚠️ This will delete your config and sweep checkpoint (if any) and run setup again. Reply 'yes' to confirm." If yes: delete `.claude/dev-agent.json` and `.claude/sweep-checkpoint.json` if it exists, then run Config Setup from scratch.

**Validate:** Test each integration with a lightweight read-only call:
- GitHub: `gh api repos/{REPO}` — expect 200
- Jira: for each project key in `{jira_project}` (split on `,`), fetch project details via Atlassian MCP using `{jira_domain}` — expect success for each
- Slack: look up `{slack_channel}` via Slack MCP — expect channel found
- Base branch: `git ls-remote --heads origin {base_branch}` — expect non-empty output

Report pass/fail per integration:
```
## Config Validation
✅ GitHub — C-FO/baberu (accessible)
✅ Jira — HQA project found at your-org.atlassian.net
❌ Slack — channel #team-dev-agent not found (check channel name or MCP permissions)
✅ Base branch — main exists on remote
```
If any fail: suggest the specific fix (wrong channel name, missing MCP, repo not found, branch name typo, etc.).
