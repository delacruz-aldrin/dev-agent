# Mode: audit

## Phase 0 — Recon
Read config. Run Backend Detection. Run Frontend Detection.

Read silently based on `BE_FRAMEWORK`:
- `rails`: `Gemfile`, `Gemfile.lock`, `config/routes.rb`, `app/` structure, `config/`
- `express`: root `package.json`, `routes/`, `src/` structure
- `django`/`fastapi`: `requirements.txt`/`pyproject.toml`, `urls.py`/`routers/`, app structure
- `go`: `go.mod`, router files, project structure
- Always: `{FRONTEND_ROOT}` structure, `{FRONTEND_ROOT}/package.json`, `tsconfig.json`, `vite.config.*`

## Phase 1 — XML
```xml
<prompt>
  <context>[Stack (BE_FRAMEWORK + version, STORE, API_CLIENT), architecture, key deps]</context>
  <files>[Key files across BE and FE, line counts, complexity flags]</files>
  <task>
    1. Top 3 highest-risk issues causing production bugs or performance degradation?
    2. Architectural inconsistencies slowing future development (BE and FE)?
    3. Which files to refactor first and why?
    4. Security concerns (XSS, token handling, exposed secrets, injection)?
    5. Frontend risks: stale state, missing loading/error states, type safety gaps, API contract mismatches?
    6. [Additional questions from recon findings]
  </task>
  <constraints>
    - Cover BE and FE. No wholesale rewrites. Actionable fixes only.
    - Flag mocks/stubs/TODOs as risks. No new deps.
    - Note critical paths with no specs/tests.
    - Flag BE/FE contract mismatches (response shape vs TS interfaces).
  </constraints>
</prompt>
```

## Phase 2 — Report
```
## Audit Report — [Project]
### Top Production Risks | ### Architectural Issues | ### Refactor Priority
### Security Concerns | ### Coverage Gaps | ### Frontend Risks | ### BE/FE Contract Gaps
```

## Phase 3 — Ticket Creation
Show all 🔴 and 🟡 findings numbered. Ask:
1. "Which findings to create as Jira tickets? Reply with numbers or 'all'."
2. "Assign to you or leave unassigned? Reply 'me' or 'unassigned'."
3. "I'll create tickets in {jira_project}. Correct? Reply 'yes' or provide a different key."

**Deduplication check:** Before creating each ticket, search Jira via Atlassian MCP:
`project = {jira_project} AND summary ~ "{short finding summary}" AND resolution = Unresolved`
If a matching open ticket is found: skip creation, note the existing ticket key in the report under **Already Tracked** instead.

Create each (not already tracked) via Atlassian MCP (cloudId = `{jira_domain}`):
- 🔴 → Bug, High priority
- 🟡 → Improvement, Medium priority
- Description: what/where, why it's a problem, expected state, suggested fix, related risks

```
## Tickets Created
| # | Type | Priority | Summary | Ticket |
|---|------|----------|---------|--------|

## Already Tracked
| # | Finding | Existing Ticket |
|---|---------|----------------|
```
