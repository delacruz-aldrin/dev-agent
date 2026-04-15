# Mode: verify

## Usage

```
/dev-agent verify [Jira link or ticket key] [PR link or number]
/dev-agent verify [Jira link or ticket key] [PR link or number] --comment
```

Pre-merge root cause check. Independently traces the affected code path in the live codebase and compares it against what the PR actually changed — surfaces gaps, missing specs, BE/FE contract mismatches, and new risks.

**Both arguments required.** By default, read-only — does not modify files or post GitHub comments. Pass `--comment` to post the findings as a GitHub COMMENT review on the PR instead of just printing.

**Examples:**
```
/dev-agent verify HQA-37771 519
→ Fetches ticket + PR #519 diff, traces the endpoint independently, reports verdict with blocking/non-blocking findings

/dev-agent verify HQA-37771 https://github.com/C-FO/baberu/pull/519
→ Same via full URL

/dev-agent verify MULTI-456 502
→ Works across any configured project
```

**When to use:**
- Before merging a PR you're not sure about
- After a refix to confirm the corrected diagnosis actually holds
- As a second opinion on a PR that looks right but feels off

---

## Phase 0 — Setup
Read config. Accept `/dev-agent verify [Jira link] [PR link] [--comment]`. Detect `--comment` flag — store as `POST_COMMENT=true` or `false`.

**Atlassian MCP pre-flight:** fetch project metadata for `{jira_project}` via Atlassian MCP (cloudId = `{jira_domain}`). If it fails, stop immediately:
```
⛔ Atlassian MCP unreachable. Check authentication before continuing.
```

Read context per **Shared: Session Context** — if stack is cached and the lockfile mtime is unchanged, skip detection and use cached values; otherwise run Backend Detection and Frontend Detection. If `fix` key is present and `fix.branch` matches the PR's head branch, store `FIX_CONTEXT_AVAILABLE=true` to use as a trace hint in Phase 1.

**Prior verify check:** look for previous COMMENT reviews on this PR authored by the authenticated user:
```bash
gh api repos/{REPO}/pulls/{pr_number}/reviews --jq '[.[] | select(.user.login == "<current_user>" and .body | startswith("## Verify Report"))]'
```
If a prior verify report exists: note `PRIOR_VERIFY=true` and store the prior findings for delta comparison in Phase 2. Otherwise `PRIOR_VERIFY=false`.

- Fetch Jira ticket via Atlassian MCP (cloudId = `{jira_domain}`)
- Fetch PR + diff: `gh api repos/{REPO}/pulls/{pr_number}` and `.../files`
- Independently trace endpoint in live codebase (ignore PR diff) using `BE_ARCH_TRACE`
- Produce: PR finding vs Live trace finding

**Print Session State** before proceeding to Phase 1:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
PR_NUMBER={value} | POST_COMMENT={true/false} | PRIOR_VERIFY={true/false}
[context] fix summary loaded (branch fix/HQA-123, N files)   ← only if FIX_CONTEXT_AVAILABLE=true
```

## Phase 1 — XML
If `FIX_CONTEXT_AVAILABLE=true`: seed `<context>` with `fix.root_cause` and `fix.files_changed` from context — use as a starting point for the live trace, not as ground truth.

```xml
<analysis>
  <context>[Ticket summary, fix type, layers, PR scope — BE and FE. If FIX_CONTEXT_AVAILABLE: prior root_cause and files_changed noted here]</context>
  <files>[Changed files by layer — BE: controller/model/serializer; FE: service/hooks/component/interface]</files>
  <task>
    1. Root cause or symptom only?
    2. Live trace gaps the PR missed (BE)?
    3. Live trace gaps the PR missed (FE)?
    4. BE/FE contract mismatches: API response shape vs TS interfaces?
    5. FE consuming code updated to match API changes?
    6. Specs/tests added or updated for changed files (BE and FE)?
    7. New risks introduced?
    8. Convention consistency (BE and FE)?
  </task>
  <constraints>
    - Jira requirements only. Flag findings only — no fixes.
    - Distinguish confirmed issues from risks.
    - If live trace diverges from PR: flag as gap.
    - BE change with no FE update is a gap if the feature has a UI surface.
  </constraints>
</analysis>
```

## Phase 2 — Report
Classify each finding before including it in the report:
- 🔴 **Blocking** — would cause a bug, regression, or security issue in production; PR should not merge as-is
- 🟡 **Non-blocking** — suboptimal but not a correctness issue; suggest as improvement
- 🟢 **Positive** — worth calling out explicitly

If `PRIOR_VERIFY=true`: compare current findings against the prior report. Tag each finding as:
- `NEW` — not in the prior report
- `RESOLVED` — was in the prior report, no longer present
- `PERSISTED` — still present from the prior report

Lead the report with a delta summary: "N new findings, M resolved since last verify, P persisted."

```
## Verify Report — [Ticket] / [PR]
### Verdict (SAFE TO MERGE / DO NOT MERGE / NEEDS DISCUSSION)
  - SAFE TO MERGE — no blocking findings
  - DO NOT MERGE — one or more blocking findings present
  - NEEDS DISCUSSION — no blockers but non-trivial suggestions or ambiguous risks
### Delta (if PRIOR_VERIFY=true): N new | M resolved | P persisted
### Root Cause Assessment
### PR vs Live Trace (BE) | ### PR vs Live Trace (FE)
### BE/FE Contract Gaps | ### Spec Coverage (BE) | ### Test Coverage (FE)
### New Risks | ### Convention Consistency
### Findings
| # | Severity | Status | File | Finding |
|---|----------|--------|------|---------|
```

If `POST_COMMENT=true`: post the full report body as a COMMENT review via:
```bash
gh api repos/{REPO}/pulls/{pr_number}/reviews -X POST \
  -f event="COMMENT" \
  -f body="<verify report markdown>"
```
Note the posted review URL in the report.

Write context per **Shared: Session Context** — record `verify` key: verdict, blocking_findings (array of 🔴 finding texts), pr_number, timestamp.
