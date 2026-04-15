# Mode: audit

## Usage

```
/dev-agent audit
```

Scans the full codebase, surfaces risks and architectural issues, and optionally creates Jira tickets for each finding.

**No arguments needed.** Reads repo structure automatically. At the end, asks which findings to file as tickets, who to assign, and which Jira project to target.

**Examples:**
```
/dev-agent audit
→ Produces an Audit Report across BE and FE, then offers to create tickets for 🔴 and 🟡 findings
```

---

## Phase 0 — Recon
Read config. Run Backend Detection. Run Frontend Detection.

Run **Shared: Frontend Convention Sampling** (unconditionally — audit always needs a grounded picture of FE patterns). Store sampled patterns as `FE_CONVENTIONS` for use in Phase 1 XML.

**BE convention sampling:** find the closest existing controller (+ usecase/interactor if applicable), serializer/blueprint, and spec. Read one of each. Store as `BE_CONVENTIONS` for use in Phase 1 XML. This grounds the audit in current conventions and allows accurate detection of inconsistencies.

**Prior audit state:** check for `.claude/dev-agent-audit-state.json` in the project root.
- If found: load `previous_hashes` (hash → first seen date) and `run_counts` (hash → number of consecutive runs persisted). Set `PRIOR_STATE=true`.
- If not found: set `PRIOR_STATE=false`, initialize both maps empty.

Read silently based on `BE_FRAMEWORK`:
- `rails`: `Gemfile`, `Gemfile.lock`, `config/routes.rb`, `app/` structure, `config/`
- `express`: root `package.json`, `routes/`, `src/` structure
- `django`/`fastapi`: `requirements.txt`/`pyproject.toml`, `urls.py`/`routers/`, app structure
- `go`: `go.mod`, router files, project structure
- Always: `{FRONTEND_ROOT}` structure, `{FRONTEND_ROOT}/package.json`, `tsconfig.json`, `vite.config.*`

**Print Session State** before proceeding to Phase 1:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
PRIOR_STATE={true/false}
```

## Phase 1 — XML
```xml
<analysis>
  <context>[Stack (BE_FRAMEWORK + version, STORE, API_CLIENT), architecture, key deps]</context>
  <files>[Key files across BE and FE, line counts, complexity flags]</files>
  <conventions>[BE_CONVENTIONS — sampled controller/usecase/serializer/spec patterns; FE_CONVENTIONS — sampled components/hooks/interfaces; omit FE block if FRONTEND_ROOT=none]</conventions>
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
</analysis>
```

## Phase 2 — Report
For each finding, compute a short hash (finding type + file + description, first 8 chars of SHA). Tag each finding:
- `NEW` — hash not in `previous_hashes` (or `PRIOR_STATE=false`). Set `run_count=1`.
- `PERSISTED` — hash present in `previous_hashes`, include first-seen date. Increment `run_count` from `run_counts` map (or start at 1 if not present).
- `RESOLVED` — hash was in `previous_hashes` but the issue no longer exists (include in a Resolved section).

**Persistence escalation:** after tagging, apply escalation to PERSISTED findings:
- If `run_count >= 3` AND original severity is 🟡: escalate to 🔴. Mark as `escalated: true`. Show in report with `↑` suffix: `🔴↑ (escalated from 🟡 — persisted {run_count} runs)`.
- Never escalate in reverse (🔴 never becomes 🟡). Never escalate NEW findings.

After generating the report, write updated state back to `.claude/dev-agent-audit-state.json`:
```json
{
  "previous_hashes": { "<hash>": "<ISO8601 first-seen date>", ... },
  "run_counts": { "<hash>": <number>, ... }
}
```
Include all current findings (NEW + PERSISTED). Drop RESOLVED findings from both maps.

Write context per **Shared: Session Context** — write `_audit.json` with `audited_at` (now) and all current (NEW + PERSISTED) findings: hash, report_index (1-based position in the numbered list), severity (effective — post-escalation), escalated (true/false), run_count, file (primary file implicated), summary (one-line description).

If `PRIOR_STATE=true`: lead the report with: "Delta since last audit: N new, M persisted, P resolved."

```
## Audit Report — [Project]
### Delta (if PRIOR_STATE=true): N new | M persisted | P resolved
### Top Production Risks | ### Architectural Issues | ### Refactor Priority
### Security Concerns | ### Coverage Gaps | ### Frontend Risks | ### BE/FE Contract Gaps
```

## Phase 3 — Ticket Creation
**Atlassian MCP pre-flight:** before asking the user anything, verify the MCP is reachable — fetch project metadata for `{jira_project}` via Atlassian MCP (cloudId = `{jira_domain}`). If it fails:
```
⚠️  Atlassian MCP unreachable — cannot create Jira tickets.
Findings are listed above. Run /dev-agent audit again or fix MCP auth to file tickets.
```
Stop Phase 3 here (do not ask further ticket questions). The audit report from Phase 2 is still complete and useful.

Show all 🔴 and 🟡 findings numbered. Ask:
1. "Which findings to create as Jira tickets? Reply with numbers or 'all'."

**Ticket volume cap:** after the user's selection is parsed, count the selected findings. If count > 5: pause before creating any tickets:
```
⚠️  You've selected {count} findings for ticket creation. That's a lot at once.
Consider batching — creating too many tickets at once can overwhelm the backlog.
Proceed with all {count}? (yes / reduce to top 5 by severity / pick different numbers)
```
Wait for response:
- `yes` → proceed with the full selection; continue to question 2
- `reduce to top 5 by severity` → take the 5 highest-severity findings (🔴 first, then 🟡 by order); update selection, confirm the reduced list to the user, then continue to question 2
- `pick different numbers` → re-show the numbered finding list and re-ask question 1; repeat the cap check with the new selection
2. "Assign to you or leave unassigned? Reply 'me' or 'unassigned'."
3. If `{jira_project}` contains multiple keys (e.g. `MULTI,HQA`): "Which project should I create tickets in? ({jira_project})" — wait for a single key. If single key: "I'll create tickets in {jira_project}. Correct? Reply 'yes' or provide a different key." Store the chosen key as `TARGET_PROJECT`.

**Deduplication check:** Before creating each ticket, search Jira via Atlassian MCP. Sanitize the finding summary before interpolating it into JQL: remove double-quotes (`"`), square brackets (`[`, `]`), JQL reserved words (`AND`, `OR`, `NOT`, `IN`, `IS`, `WAS`, `ORDER`, `BY`), and any other special characters (`~`, `*`, `?`, `+`, `-`) — then truncate to 60 characters to avoid malformed queries:
`project = {TARGET_PROJECT} AND summary ~ "{sanitized finding summary}" AND resolution = Unresolved`
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
