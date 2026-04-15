# Mode: sweep

## Usage

```
/dev-agent sweep
/dev-agent sweep --manual "description 1, description 2, ..."
```

Pulls all open tickets assigned to you from Jira, lets you set priority order, then processes each one end-to-end — branch, fix or build, tests, PR, Jira transition, and Slack notification — sequentially.

**No arguments** — automatically queries `{jira_project}` for your assigned open tickets. Supports resuming from a checkpoint if interrupted mid-sweep.

**`--manual`** — skip Jira entirely and process a comma-separated list of descriptions instead. Each item is treated as a manual input (equivalent to `/dev-agent fix "description"` or `/dev-agent build "description"`). No Jira transitions or ticket deduplication. Use this when tickets don't exist yet or you're working outside Jira.

**Examples:**
```
/dev-agent sweep
→ Finds 4 open tickets assigned to you, presents them grouped by type (bugs first),
  waits for your priority order, then processes each one fully before moving to the next

/dev-agent sweep   ← after an interrupted sweep
→ Detects .claude/sweep-checkpoint.json, shows completed tickets, asks to resume or start fresh
```

**When to use vs fix/build:**
- Use `sweep` for a batch of tickets at once (end-of-sprint, clearing backlog)
- Use `fix` or `build` for a single ticket when you want to stay hands-on

---

## Phase 0 — Setup + Board Scan
Read config. Run Backend Detection. Run Frontend Detection.

**MCP pre-flight:** run both checks before any further steps. If either fails, stop immediately.

- **Atlassian MCP:** fetch project metadata for `{jira_project}` (cloudId = `{jira_domain}`). Failure:
  ```
  ⛔ Atlassian MCP unreachable. Check authentication before continuing.
  ```
- **Slack MCP:** look up `#{slack_channel}`. Failure:
  ```
  ⛔ Slack MCP unreachable. Check authentication before continuing.
  ```

Detect `--manual` flag. If present: parse the comma-separated descriptions into a `MANUAL_ITEMS` list. Route each item to fix or build based on description keywords (verbs like "fix", "bug", "broken", "broken" → fix mode; all others → build mode). Then present the routing plan and require confirmation before continuing:
```
Manual sweep — routing plan:
| # | Description | Mode |
|---|-------------|------|
| 1 | "fix login bug" | fix |
| 2 | "add export endpoint" | build |

Correct? (yes / change N to fix|build / remove N)
```
Wait for `yes` or adjustments before proceeding. After confirmation, skip checkpoint and Jira query steps and jump directly to Phase 1 using the confirmed `MANUAL_ITEMS` list. Each item has `TICKET_KEY=none`.

Switch to main:
```bash
git checkout {base_branch} && git pull origin {base_branch}
```
If checkout fails (uncommitted changes), stop:
```
⛔ Uncommitted changes detected. Stash (`git stash`) or commit before running /dev-agent sweep.
```

**Checkpoint:** Check for a `.claude/sweep-checkpoint.json` in the project root. If it exists:
- Read it and display: "Found a previous sweep checkpoint. The following tickets were already completed: [list]. Resume from where it left off? Reply 'yes' or 'no' (no = start fresh)."
- If 'yes': skip already-completed tickets in Phase 2. For any ticket in `in_progress`, resume from the step after `last_milestone` (see milestone table in Phase 2). If the checkpoint includes a `detection_cache`, load it directly — skip re-running Backend/Frontend Detection. If 'no': delete the file and start fresh.
- If no file: create it with the initial structure below before processing begins. Also ensure `.claude/sweep-checkpoint.json` is listed in `.gitignore` — if not, append it silently.

Initial checkpoint structure (written at the start of Phase 0, updated throughout):
```json
{
  "completed": [],
  "in_progress": null,
  "detection_cache": {
    "BE_FRAMEWORK": "rails",
    "FRONTEND_ROOT": "front/",
    "STORE": "tanstack-query",
    "API_CLIENT": "orval",
    "BE_TEST_CMD": "bundle exec rspec",
    "BE_LINT_FIX": "bundle exec rubocop -a",
    "BE_LINT_CHECK": "bundle exec rubocop",
    "BE_FORMAT_CMD": "bundle exec stree write",
    "API_GEN_CMD": "yarn generate-client",
    "FE_TEST": "vitest",
    "FE_TEST_CMD": "yarn test",
    "FE_LINT": "biome",
    "FE_LINT_FIX": "yarn lint:fix",
    "FE_LINT_CHECK": "yarn lint"
  }
}
```
Write `detection_cache` immediately after Backend/Frontend Detection completes in Phase 0 — include all resolved variables: `BE_FRAMEWORK`, `FRONTEND_ROOT`, `STORE`, `API_CLIENT`, `BE_TEST_CMD`, `BE_LINT_FIX`, `BE_LINT_CHECK`, `BE_FORMAT_CMD` (store `null` if not applicable to the framework), `API_GEN_CMD` (store `null` if `API_CLIENT≠orval` or no generate command found), `FE_TEST`, `FE_TEST_CMD`, `FE_LINT`, `FE_LINT_FIX`, `FE_LINT_CHECK`. On resume, if `detection_cache` is present, restore all variables from it and skip re-running detection. Invalidate the cache (re-run detection and overwrite) if `package.json`, `Gemfile`, or `go.mod` has been modified since the checkpoint was written — compare file mtimes using `stat`.

**Per-ticket context precedence:** when processing each ticket in Phase 2, check for a per-ticket context file (`.claude/dev-agent/context/{TICKET_KEY}.json`) per **Shared: Session Context**. If present and stack is still valid (lockfile mtime + 7-day checks pass), use it — it takes precedence over `detection_cache` for that ticket. If absent or stale, fall back to `detection_cache` — this satisfies the **Shared: Session Context** "re-detect on stale" rule because `detection_cache` already holds a freshly-run detection result from Phase 0 (do not re-run detection again per ticket inside sweep). This means a prior `fix` or `build` run on the same ticket carries forward its cached stack into sweep processing.

**Print Session State** before querying tickets:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
```

Query tickets via Atlassian MCP (cloudId = `{jira_domain}`). Expand `{jira_project}` using JQL Project Expansion from SKILL.md (e.g. `MULTI,HQA` → `project in (MULTI, HQA)`). Try JQL in order until results:
1. `{project_clause} AND assignee = currentUser() AND status in ("To Do", "In Progress") AND issuetype in (Bug, Story, Task, Improvement, Sub-task)`
2. `{project_clause} AND assignee = currentUser() AND status in ("To Do", "In Progress")`
3. `{project_clause} AND assignee = currentUser() AND statusCategory in ("To Do", "In Progress")`
4. `{project_clause} AND assignee = currentUser() AND resolution = Unresolved`

If all four return zero:
```
No open tickets found in {jira_project}. Tried 4 JQL variations.
If tickets exist, let me know and I'll adjust the query.
```

## Phase 1 — Prioritization
Present grouped (🐛 Bugs first, then 📋 Stories/Tasks/Improvements/Sub-tasks). Ask for priority order. Wait for confirmation before proceeding.

**Scope preview** — after priority order is confirmed, show a summary before any code runs:
```
Sweep scope — N tickets queued:
| # | Ticket | Type | Branch |
|---|--------|------|--------|
| 1 | HQA-123 | Bug → fix | bug/HQA-123 |
| 2 | HQA-456 | Story → build | feat/HQA-456 |

Proceed? (yes / drop N / reorder)
```
Wait for final confirmation before starting Phase 2.

## Phase 2 — Sequential Processing
Route: Bug → fix mode, everything else → build mode. For each ticket:

**Gates suppressed in sweep mode** — sweep is autonomous; do not pause at interactive gates. Set session variable `SWEEP_MODE=active` at the start of Phase 2 (before the first ticket). The following gates defined in fix and build check this variable and skip when it is set:
- Pre-commit review gate ("Ready to commit?")
- Auto-verify offer (refix only)

If the user wants to review changes before committing, they should run fix or build individually rather than sweep.

1. Pull latest main before branching:
   ```bash
   git checkout {base_branch} && git pull origin {base_branch}
   ```
2. Run fix or build mode fully (including FE steps per detected stack), suppressing the gates listed above — if tests fail after auto-fix: revert, note in sweep report, skip
3. PR creation is part of fix/build — verify labels, milestone, reviewer via `gh api` — if fails: note in report and continue
4. Transition to "For Review" via Atlassian MCP — if fails: note in report and continue
5. Run **Shared: Post Slack Thread** — look up `{slack_group}` once, reuse for all tickets. Each ticket must use a different angle.
6. **Update checkpoint:** write progress to `.claude/sweep-checkpoint.json` after every named milestone — not just on ticket completion. Checkpoint structure:
   ```json
   {
     "completed": ["HQA-1", "HQA-2"],
     "in_progress": {
       "key": "HQA-3",
       "last_milestone": "branch_created",
       "branch": "bug/HQA-3",
       "pr_number": null
     }
   }
   ```

   Named milestones in order — write `last_milestone` immediately after each one completes:
   | Milestone | Written after |
   |---|---|
   | `branch_created` | `git checkout -b` succeeds |
   | `code_applied` | all file changes written |
   | `tests_passed` | `{BE_TEST_CMD}` (and FE tests if applicable) green |
   | `quality_checked` | lint + format clean |
   | `pr_created` | `gh api` PR creation returns `PR_NUMBER` — also write `pr_number` to `in_progress` at this point |
   | `jira_transitioned` | Jira status updated to "For Review" |
   | `slack_posted` | Slack thread posted |

   - On ticket completion: move key to `completed`, clear `in_progress`
   - On resume: if `in_progress` exists with a `last_milestone`, skip all steps up to and including that milestone for that ticket, then continue from the next one. If resuming after `pr_created` and `in_progress.pr_number` is set, restore `PR_NUMBER` from it. If `pr_number` is null (checkpoint written by an older version), re-fetch it: `gh pr list --head {branch} --repo {REPO} --state open --json number --jq '.[0].number'`

## Phase 3 — Sweep Report
```
## Sweep Report
### Summary | ### Results (table) | ### Skipped Tickets | ### Errors
```
Delete `.claude/sweep-checkpoint.json` after producing the final report.

**Safety:** one ticket at a time, never partial, only transition to "For Review". BE and FE linting must pass before any PR. If FE tests fail after auto-fix: revert FE changes, raise PR with BE-only, note in report.
