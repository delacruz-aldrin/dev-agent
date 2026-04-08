# Mode: fix

## Usage

```
/dev-agent fix [Jira link or ticket key]
/dev-agent fix [manual description]
```

Diagnoses a bug and opens a PR with the fix, specs, and Slack notification.

**With a Jira ticket** — fetches the ticket, traces the affected code path, fixes the root cause, runs tests, opens a PR, and transitions the ticket to "For Review".

**Manual** — use a plain description when there's no ticket yet.

**Examples:**
```
/dev-agent fix HQA-37771
→ Fetches ticket, traces controller → usecase → model, applies scoped fix, opens PR

/dev-agent fix https://jira-freee.atlassian.net/browse/HQA-37771
→ Same as above via full URL

/dev-agent fix The page list table has wrong column widths when there are no pages
→ Manual input — creates branch fix/manual-page-list-column-widths
```

---

## Phase 0 — Setup
Read config. Run Backend Detection. Run Frontend Detection.

Switch to main:
```bash
git checkout {base_branch} && git pull origin {base_branch}
```
If checkout fails (uncommitted changes), stop:
```
⛔ Uncommitted changes detected. Stash (`git stash`) or commit before running /dev-agent fix.
```

**Breaking-change guard:** after pulling, check if any files in the traced path were modified by the pull:
```bash
git diff HEAD@{1} HEAD --name-only
```
If the pull changed files that overlap with the likely trace path (routes, controllers, models, serializers, key FE files), warn: "main was updated and the following traced files changed: [list]. Review these changes before branching? (yes to pause / no to continue)". Wait for response.

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
- **missing feature / not implemented** → treat as a scoped build within fix flow: generate only the missing layer(s) per `BE_ARCH_TRACE`, do not restructure existing code, use fix branch naming (`bug/` or `fix/manual-`)

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
10. **Pre-commit review gate:** show a summary of all changed files and a brief description of each change, then ask: "Ready to commit? (yes / review / revert all)".
    - `yes` → proceed
    - `review` → show full diff of each changed file, then re-ask
    - `revert all` → revert all changes, note in report, stop
11. Commit and push:
   ```bash
   git add {every file changed in this fix}   # list files explicitly — never use git add . or git add -A
   git commit -m "fix: [short description]"
   git push origin HEAD
   ```
12. Run **Shared: Create PR** with `TICKET_KEY` (or `none` if manual). Pass the Jira ticket URL as the ticket link.
13. Transition Jira to "For Review" via Atlassian MCP — if fails: note in report and continue
14. If standalone (not via sweep): run **Shared: Post Slack Thread**

```
## Bug Report — [Endpoint]
### Root Cause | ### Affected Files (BE + FE) | ### Fix Applied
### Test Suite | ### Related Risks | ### Jira Status | ### PR
```
