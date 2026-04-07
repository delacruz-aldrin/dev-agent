---
name: dev-agent
description: Ten-mode dev agent + config utility. Modes: audit (codebase assessment), fix (bug diagnosis+fix), refix (re-diagnose and fix a rejected/reverted deployment), build (generate endpoints), verify (PR root cause check), sweep (autonomous Jira→PR pipeline), respond (address PR comments), review (review colleague PRs), follow-up (Slack nudge for PR review), setup (follow setup docs and configure local environment with rollback support). Use "dev-agent config" to view, edit, or reset project config. Always reads settings from .claude/dev-agent.json.
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
| `/dev-agent config` | See **Utility: Config** below |

---

## Shared: Config System

### Config File
`.claude/dev-agent.json` in project root. Committed to repo — shared across teammates.

```json
{
  "repo": "owner/repo",
  "jira_domain": "your-org.atlassian.net",
  "jira_project": "MULTI,HQA",
  "slack_channel": "team-dev-agent",
  "slack_group": "likha-dev-agent-eng",
  "pr_reviewer_team": "dev-agent",
  "pr_milestone": "Untracked"
}
```

### Known Config Keys
The canonical key list (used for missing-key detection and validation):

| Key | Format | Example |
|---|---|---|
| `repo` | `owner/repo` — must contain exactly one `/` | `C-FO/baberu` |
| `jira_domain` | hostname only, no protocol | `your-org.atlassian.net` |
| `jira_project` | one or more uppercase alphanumeric keys, comma-separated (spaces around commas are accepted and stripped on save) | `MULTI` or `MULTI, HQA` |
| `slack_channel` | no `#` prefix | `team-dev-agent` |
| `slack_group` | handle, no `@` | `likha-dev-agent-eng` |
| `pr_reviewer_team` | GitHub team slug | `dev-agent` |
| `pr_milestone` | exact milestone name | `Untracked` |

### JQL Project Expansion
Whenever a mode builds a JQL query using `{jira_project}`, always expand it first:
- Parse `jira_project` by splitting on `,` and trimming whitespace → `JIRA_PROJECTS` array
- Single entry → use `project = KEY`
- Multiple entries → use `project in (KEY1, KEY2)`

Never interpolate `{jira_project}` raw into JQL.

### First Run Detection
At Phase 0 of every mode: read `.claude/dev-agent.json` if it exists. Diff its keys against the Known Config Keys list.
- File missing entirely → run **Config Setup** (all keys)
- File exists but some keys missing → run **Config Setup** for missing keys only, preserve existing values
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

Report pass/fail per integration:
```
## Config Validation
✅ GitHub — C-FO/baberu (accessible)
✅ Jira — HQA project found at your-org.atlassian.net
❌ Slack — channel #team-dev-agent not found (check channel name or MCP permissions)
```
If any fail: suggest the specific fix (wrong channel name, missing MCP, repo not found, etc.).
