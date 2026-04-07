# Mode: verify

## Usage

```
/dev-agent verify [Jira link or ticket key] [PR link or number]
```

Pre-merge root cause check. Independently traces the affected code path in the live codebase and compares it against what the PR actually changed — surfaces gaps, missing specs, BE/FE contract mismatches, and new risks.

**Both arguments required.** Does not modify any files or post GitHub comments — read-only analysis only.

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
Read config. Accept `/dev-agent verify [Jira link] [PR link]`.

- Fetch Jira ticket via Atlassian MCP (cloudId = `{jira_domain}`)
- Fetch PR + diff: `gh api repos/{REPO}/pulls/{pr_number}` and `.../files`
- Independently trace endpoint in live codebase (ignore PR diff) using `BE_ARCH_TRACE`
- Produce: PR finding vs Live trace finding

## Phase 1 — XML
```xml
<prompt>
  <context>[Ticket summary, fix type, layers, PR scope — BE and FE]</context>
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
</prompt>
```

## Phase 2 — Report
Classify each finding before including it in the report:
- 🔴 **Blocking** — would cause a bug, regression, or security issue in production; PR should not merge as-is
- 🟡 **Non-blocking** — suboptimal but not a correctness issue; suggest as improvement
- 🟢 **Positive** — worth calling out explicitly

```
## Verify Report — [Ticket] / [PR]
### Verdict (APPROVE / REQUEST_CHANGES / COMMENT)
### Root Cause Assessment
### PR vs Live Trace (BE) | ### PR vs Live Trace (FE)
### BE/FE Contract Gaps | ### Spec Coverage (BE) | ### Test Coverage (FE)
### New Risks | ### Convention Consistency
### Findings
| # | Severity | File | Finding |
|---|----------|------|---------|
```
