# Mode: sweep

## Phase 0 — Setup + Board Scan
Read config. Run Backend Detection. Run Frontend Detection.

Switch to main:
```bash
git checkout main && git pull origin main
```
If checkout fails (uncommitted changes), stop:
```
⛔ Uncommitted changes detected. Stash (`git stash`) or commit before running /dev-agent sweep.
```

**Checkpoint:** Check for a `.claude/sweep-checkpoint.json` in the project root. If it exists:
- Read it and display: "Found a previous sweep checkpoint. The following tickets were already completed: [list]. Resume from where it left off? Reply 'yes' or 'no' (no = start fresh)."
- If 'yes': skip already-completed tickets in Phase 2. If 'no': delete the file and start fresh.
- If no file: create it as `{ "completed": [] }` before processing begins. Also ensure `.claude/sweep-checkpoint.json` is listed in `.gitignore` — if not, append it silently.

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

## Phase 2 — Sequential Processing
Route: Bug → fix mode, everything else → build mode. For each ticket:

1. Pull latest main before branching:
   ```bash
   git checkout main && git pull origin main
   ```
2. Run fix or build mode fully (including FE steps per detected stack) — if tests fail after auto-fix: revert, note in sweep report, skip
3. PR creation is part of fix/build — verify labels, milestone, reviewer via `gh api` — if fails: note in report and continue
4. Transition to "For Review" via Atlassian MCP — if fails: note in report and continue
5. Run **Shared: Post Slack Thread** — look up `{slack_group}` once, reuse for all tickets. Each ticket must use a different angle.
6. **Update checkpoint:** append the completed `TICKET_KEY` to `.claude/sweep-checkpoint.json`:
   ```json
   { "completed": ["HQA-1", "HQA-2", ...] }
   ```
   Write this after every successfully processed ticket — even if PR/Slack steps failed — so a resume skips re-doing the code work.

## Phase 3 — Sweep Report
```
## Sweep Report
### Summary | ### Results (table) | ### Skipped Tickets | ### Errors
```
Delete `.claude/sweep-checkpoint.json` after producing the final report.

**Safety:** one ticket at a time, never partial, only transition to "For Review". BE and FE linting must pass before any PR. If FE tests fail after auto-fix: revert FE changes, raise PR with BE-only, note in report.
