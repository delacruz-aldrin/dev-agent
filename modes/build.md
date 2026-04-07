# Mode: build

## Usage

```
/dev-agent build [Jira link or ticket key]
/dev-agent build [manual description]
```

Generates a complete feature implementation — backend endpoint, frontend integration, specs, and PR.

**With a Jira ticket** — reads the acceptance criteria, samples existing conventions, generates all layers (route → controller → usecase → serializer → specs, plus TS interfaces, API client, component), then opens a PR.

**Manual** — describe the feature directly when there's no ticket.

**Examples:**
```
/dev-agent build HQA-35223
→ Reads ticket, samples similar controllers and components, generates full endpoint + FE integration

/dev-agent build MULTI-456
→ Same — works with any configured Jira project

/dev-agent build Add a GET /api/p/nodes/:id endpoint that returns a single node with its translations
→ Manual input — creates branch feat/manual-get-node-with-translations
```

---

## Phase 0 — Setup
Read config. Run Backend Detection. Run Frontend Detection.

Switch to main:
```bash
git checkout main && git pull origin main
```
If checkout fails (uncommitted changes), stop:
```
⛔ Uncommitted changes detected. Stash (`git stash`) or commit before running /dev-agent build.
```

Detect input (Jira link or manual). Derive `TICKET_KEY`.
Create branch per **Shared: Create Branch**.

Sample silently:
- **Backend:** closest existing controller (+ usecase/interactor if `BE_FRAMEWORK=rails`), serializer/blueprint, spec
- **Frontend:** per **Shared: Frontend Convention Sampling**

## Phase 1 — XML
```xml
<prompt>
  <context>[Stack (BE_FRAMEWORK, STORE, API_CLIENT), namespace, auth pattern, endpoint description]</context>
  <conventions>[Sampled BE + FE patterns]</conventions>
  <task>
    Backend (skip sections not applicable to BE_FRAMEWORK):
    1. Route entry
    2. Controller following existing conventions
    3. Business logic layer (usecase/service/handler per BE_FRAMEWORK)
    4. Serializer/blueprint/response object
    5. OpenAPI schema fragment (if applicable — co-located with controller)
    6. BE specs/tests

    Frontend (skip if FRONTEND_ROOT=none or purely BE ticket):
    7. TS interface(s) for new/changed response shape
    8. API client integration (orval: note it will be regenerated — do not hand-write; manual: service method matching sampled pattern)
    9. State update if needed (per STORE — omit if not needed, note explicitly)
    10. React component or page
    11. Frontend tests (if FE_TEST≠none)
  </task>
  <constraints>
    - Match existing naming exactly. No new deps.
    - Every new API endpoint needs frontend integration (per API_CLIENT).
    - Include specs/tests for all files. Flag ambiguous decisions.
    - If no state update needed, note explicitly — don't add unnecessary state.
    - If purely BE ticket (no UI surface), note and skip FE steps.
  </constraints>
</prompt>
```

## Phase 2 — Execute
1. Write all BE files to correct paths
2. Update routes
3. If `BE_FRAMEWORK=rails`:
   - If the feature requires new or altered DB columns/tables: generate a migration (`bundle exec rails generate migration ...`), verify the migration file, then run `bundle exec rails db:migrate`. Note: services must be running (`make services.up`) for migrations to work.
   - Create co-located `.openapi.yml` fragment, run `{API_GEN_CMD}`
4. Create/update BE specs for all generated and modified files
5. Write FE files (interfaces, component; service only if `API_CLIENT=manual`)
6. Run `{BE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert all changes, note in report, stop
7. If `FE_TEST≠none`: run `{FE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert FE changes, note in report
8. Run **Shared: Run Quality Checks**
9. Commit and push:
   ```bash
   git add {every file changed in this build}   # list files explicitly — never use git add . or git add -A
   git commit -m "feat: [short description]"
   git push origin HEAD
   ```
10. Create PR: `/pr {ticket link or 'no ticket'}`
    - Verify labels (`ai-contribution-level:3`), milestone (`{pr_milestone}`), reviewer (`{pr_reviewer_team}`) — apply missing via `gh api`
11. Transition Jira to "For Review" via Atlassian MCP — if fails: note in report and continue
12. If standalone: run **Shared: Post Slack Thread**

```
## New Feature — [Name]
### BE Files Written | ### Route | ### Controller | ### Serializer | ### OpenAPI Fragment | ### Specs
### FE Files Written | ### TS Interfaces | ### Client | ### State | ### Component
### Ambiguity Flags | ### Test Suite | ### Jira Status | ### PR
```
