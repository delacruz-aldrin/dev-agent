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
Read config. Read context per **Shared: Session Context** — if stack is cached and the lockfile mtime is unchanged, skip Backend/Frontend Detection and use cached values; otherwise run Backend Detection and Frontend Detection.

**Atlassian MCP pre-flight (Jira input only):** if input appears to be a Jira link or ticket key (matches `[A-Z]+-[0-9]+` or contains `{jira_domain}`), fetch project metadata for `{jira_project}` via Atlassian MCP (cloudId = `{jira_domain}`). If it fails, stop immediately:
```
⛔ Atlassian MCP unreachable. Check authentication before continuing.
```
Skip this check for manual descriptions.

Switch to main:
```bash
git checkout {base_branch} && git pull origin {base_branch}
```
If checkout fails (uncommitted changes), stop:
```
⛔ Could not switch to {base_branch}. If you have uncommitted changes, stash (`git stash`) or commit them first. Otherwise check that {base_branch} exists and the remote is reachable.
```

Detect input (Jira link or manual). Derive `TICKET_KEY`.

**Duplicate endpoint guard:** if the input or ticket description specifies an HTTP method + path (e.g. `GET /api/p/nodes/:id`), grep the routes file for a matching pattern before branching:
- `rails`: `grep -n "nodes" config/routes.rb`
- `express`: `grep -rn "nodes" routes/`
- `django`/`fastapi`: `grep -rn "nodes" urls.py routers/`
- `go`: grep router files

If a route with the same method and path already exists: "A similar route already exists: `[method path]` at `[file:line]`. Is this a new variant or a duplicate? (variant / duplicate / cancel)". Stop if `duplicate` or `cancel`. Note `variant` in report and continue.

Create branch per **Shared: Create Branch**.

Sample silently:
- **Backend:** closest existing controller (+ usecase/interactor if `BE_FRAMEWORK=rails`), serializer/blueprint, spec
- **Frontend:** per **Shared: Frontend Convention Sampling**

**Print Session State** before proceeding to Phase 1:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
TICKET_KEY={value} | BRANCH={value}
[context] stack reused from cache   ← only if stack was loaded from context
```

## Phase 1 — XML
```xml
<analysis>
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
</analysis>
```

## Phase 2 — Execute
1. Write all BE files to correct paths
2. Update routes
3. If `BE_FRAMEWORK=rails`:
   - If the feature requires new or altered DB columns/tables: generate a migration (`bundle exec rails generate migration ...`), verify the migration file, then **inspect for destructive operations**: if the migration contains `drop_column`, `drop_table`, `change_column` (type change), `remove_index`, or `remove_reference`, pause:
     ```
     ⚠️  Destructive migration detected: [operation] on [table/column]
     This cannot be automatically rolled back in production. Confirm this is intentional. (yes / abort)
     ```
     If `abort`: stop and revert the generated migration file. If `yes`: run `bundle exec rails db:migrate`. Note: services must be running (`make services.up`) for migrations to work.
   - Create co-located `.openapi.yml` fragment, run `{API_GEN_CMD}` — skip if `API_GEN_CMD=none`, note in report
4. Create/update BE specs for all generated and modified files
5. **AC coverage check (Jira tickets only — skip if manual):** map each acceptance criterion from the Jira ticket to the files/methods generated. Produce a checklist:
   ```
   AC Coverage:
   ✅ "Users can fetch a single node" → GET /api/p/nodes/:id in nodes_controller.rb
   ❌ "Returns translations for the node" → NOT FOUND — no serializer field or FE interface includes translations
   ```
   For each uncovered AC item: "AC item [N] has no implementation. Generate it now or skip? (generate / skip)". If `generate`: implement it before continuing. Do not proceed to commit with any unresolved `generate` responses outstanding. If `skip`: record the AC item in the report under **Skipped AC Items** — do not silently drop it.
6. Write FE files (interfaces, component; service only if `API_CLIENT=manual`)
7. Run `{BE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert all changes, note in report, stop
8. If `FE_TEST≠none`: run `{FE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert FE changes, note in report
9. Run **Shared: Run Quality Checks**
10. **Pre-commit review gate** (skip if `SWEEP_MODE=active` — sweep sets this variable at Phase 2 start and suppresses all interactive gates):
    Show a summary of all generated and modified files with a brief description of each, then ask: "Ready to commit? (yes / review / revert all)".
    - `yes` → proceed
    - `review` → show full diff of each changed file, then re-ask
    - `revert all` → revert all changes, note in report, stop
11. Commit and push:
    ```bash
    git add {every file changed in this build}   # list files explicitly — never use git add . or git add -A
    git commit -m "feat: [short description]"
    git push origin HEAD
    ```
12. Run **Shared: Create PR** with `TICKET_KEY` (or `none` if manual). Pass the Jira ticket URL as the ticket link.
13. Transition Jira to "For Review" via Atlassian MCP — skip if `TICKET_KEY=none`; if fails: note in report and continue
14. If standalone: run **Shared: Post Slack Thread**
15. Write context per **Shared: Session Context** — record `stack` (if re-detected); write `build` key: `pr_number`, `pr_url`, `branch`, `timestamp`. This allows `verify` and `refix` to reference the PR after a build run.

```
## New Feature — [Name]
### BE Files Written | ### Route | ### Controller | ### Serializer | ### OpenAPI Fragment | ### Specs
### FE Files Written | ### TS Interfaces | ### Client | ### State | ### Component
### AC Coverage (omit section if manual input or all ACs covered) | ### Skipped AC Items (omit if none)
### Ambiguity Flags | ### Test Suite | ### Jira Status | ### PR
```
