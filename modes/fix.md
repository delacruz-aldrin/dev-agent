# Mode: fix

## Phase 0 — Setup
Read config. Run Backend Detection. Run Frontend Detection.

Switch to main:
```bash
git checkout main && git pull origin main
```
If checkout fails (uncommitted changes), stop:
```
⛔ Uncommitted changes detected. Stash (`git stash`) or commit before running /dev-agent fix.
```

Detect input:
- **Jira link** → fetch via Atlassian MCP (cloudId = `{jira_domain}`) — description, steps, expected, actual. Derive `TICKET_KEY` from URL.
- **Manual** → use as-is. Set `TICKET_KEY=none`.

Create branch per **Shared: Create Branch**.

## Phase 1 — XML
Trace flow using `BE_ARCH_TRACE`. Also trace frontend based on `STORE`:
- `tanstack-query` + `orval`: generated hook → component
- `tanstack-query` + other: `useQuery`/`useMutation` → component
- `redux`: service → slice/thunk → component
- `zustand`: store → component
- `none`: fetch/local state → component

Read traced files only.

Symptom → focus mapping:
- **duplicates** → deduplication, unique constraints, import flow, race conditions
- **slow/performance** → N+1, missing indexes, bulk ops; FE: unnecessary re-renders, over-fetching
- **500/error/crash** → exception handling, nil checks, edge cases; FE: unhandled rejections, missing error states
- **wrong data** → transformation, serialization, callbacks; FE: stale state, incorrect field mapping
- **auth/unauthorized** → permission checks, session handling; FE: token storage, route guards, role checks
- **UI/display bug** → FE only: component logic, conditional rendering, missing loading states

```xml
<prompt>
  <context>[Stack, endpoint, layers, symptom]</context>
  <files>[Traced files only, line counts, patterns]</files>
  <task>[Symptom-specific questions across BE and FE layers]</task>
  <constraints>
    - Traced flow only. No architectural changes. Minimal scoped fix.
    - Find exact bug location. Flag related risks. Update specs/tests for changed files.
    - If fix changes API response shape: update TS interfaces and consuming code.
  </constraints>
</prompt>
```

## Phase 2 — Execute
1. Apply fix to files (BE and FE as needed)
2. Update TS interfaces if API response shape changed
3. If `API_CLIENT=orval` and shape changed: run `{API_GEN_CMD}`
4. Update frontend consuming code (hooks/service/state/component) if affected
5. Create/update specs for every changed BE file
6. Run `{BE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert all changes, note in report, stop
7. If `FE_TEST≠none`: run `{FE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert FE changes, note in report, continue with BE-only
8. **Side-effect check** — run only if any changed file matches:
   - A shared interactor, model method, or service used by more than one usecase/controller
   - A serializer, blueprint, or anything that changes API response shape
   - A frontend hook, store slice, or utility shared across multiple components

   If triggered: grep for callers/consumers of every changed method or export. Read each caller. For each:
   - Does the change alter behavior for that caller? → flag as **at-risk**
   - Could it produce unexpected output, break an assumption, or introduce a regression? → add a spec covering that caller's scenario

   If no at-risk callers found: note "side-effect check passed, no at-risk callers" in report and continue.
   If at-risk callers found but no fix needed: document them in the report under **Related Risks**.
   If a caller needs a fix: apply it, add a spec, re-run `{BE_TEST_CMD}`.

9. Run **Shared: Run Quality Checks**
10. Commit and push:
   ```bash
   git add {every file changed in this fix}   # list files explicitly — never use git add . or git add -A
   git commit -m "fix: [short description]"
   git push origin HEAD
   ```
11. Create PR: `/pr {ticket link or 'no ticket'}`
    - Verify labels (`ai-contribution-level:3`), milestone (`{pr_milestone}`), reviewer (`{pr_reviewer_team}`) — apply missing via `gh api`
12. Transition Jira to "For Review" via Atlassian MCP — if fails: note in report and continue
13. If standalone (not via sweep): run **Shared: Post Slack Thread**

```
## Bug Report — [Endpoint]
### Root Cause | ### Affected Files (BE + FE) | ### Fix Applied
### Test Suite | ### Related Risks | ### Jira Status | ### PR
```
