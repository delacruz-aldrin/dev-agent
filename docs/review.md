# review

Reviews a colleague's PR — checks requirements, logic, tests, and conventions — then leaves inline GitHub comments, submits a formal verdict, and notifies the author on Slack.

## When to use

- You're assigned to review a colleague's PR
- You want a structured, thorough review (not just a skim)
- You ran it before and want to follow up on what's been addressed

## Usage

```
/dev-agent review [PR number or URL]
```

```
/dev-agent review 518
/dev-agent review https://github.com/org/repo/pull/518
```

**Only works on PRs you did NOT author.** If it's your own PR, use `respond` instead.

## First review vs follow-up

review auto-detects which mode to run:

- **First review** — no prior review comments from you: performs a full review from scratch
- **Follow-up** — prior comments found: re-assesses only threads that were updated since your last review

### First review

Fetches:
- PR diff, commits, and description
- Linked Jira ticket (acceptance criteria and requirements)
- Existing code conventions (samples similar files in the codebase for comparison)
- Pre-existing audit findings for the changed files

Checks every dimension:

| Area | What's checked |
|---|---|
| **Requirements** | Does the PR satisfy every Jira acceptance criterion? |
| **Logic** | Are there edge cases, nil risks, or incorrect assumptions? |
| **Test coverage (BE)** | Every changed file covered? Happy path + edge cases? Are behaviors asserted, not just executed? |
| **Test coverage (FE)** | Changed components and services covered? |
| **BE/FE contract** | Does the serializer/response shape match TypeScript interfaces? |
| **Frontend integration** | If the feature has a UI surface, is the FE updated? |
| **Security** | XSS, injection, token handling, exposed data? |
| **Performance** | N+1 queries, missing indexes, unnecessary re-renders? |
| **Conventions** | Naming, structure, and patterns consistent with the codebase? |
| **PR description** | Is it complete and accurate? |
| **New patterns** | Does the PR introduce a new abstraction worth documenting? |
| **Pre-existing audit findings** | Are there known risks in the changed files from a recent audit? |

**Urgency calibration:**
- PR open more than 7 days → ⚠️ flagged in the report; urgent tone in Slack
- PR open more than 3 days → noted in report

**Size check:** if the PR has 300+ additions or deletions, review assesses whether it should be split, and leaves a PR comment either way.

### Follow-up review

For each open thread from the previous review:

| Thread state | What happens |
|---|---|
| Author replied + code updated | Re-assesses the change |
| Author replied + code NOT updated | Responds inline |
| Author did NOT reply + code updated | Re-assesses, notes the missing reply |
| Author did NOT reply + code NOT updated | Flags as outstanding (no new comment) |

**Stale thread escalation:** if a thread has been outstanding for 3+ consecutive follow-up runs without any author response, review posts a direct GitHub comment tagging the PR author: `@author — thread on file:line has been outstanding for N follow-ups with no response. Is this still relevant?`

## Verdicts

review submits a formal GitHub review (not just a comment):

| Verdict | When |
|---|---|
| **APPROVE** | CI passes, no blocking findings, no suggestions |
| **REQUEST_CHANGES** | One or more blocking findings |
| **COMMENT** | Suggestions only, or CI not fully passed |

Findings are classified as:
- 🔴 **Blocking** — must be fixed before merging (missing tests, BE/FE contract mismatch, missing FE integration, security issues)
- 🟡 **Non-blocking** — suggestions worth considering
- 🟢 **Positive** — worth calling out

## What you'll see

```
## Review Report — Add node export endpoint (PR #518)

### Verdict: REQUEST_CHANGES

### Requirements Coverage
✅ "Users can export nodes to CSV" — covered by ExportController#csv
❌ "Export respects user permissions" — no authorization check on the export action

### Blocking Issues 🔴
1. app/controllers/exports_controller.rb:15 — No authorization check before export
   Any authenticated user can export any node, including nodes they can't view.
2. spec/controllers/exports_controller_spec.rb — No test for unauthorized access

### Suggestions 🟡
1. app/serializers/export_serializer.rb:8 — Consider using `.presence` instead of direct `.email` call for nil safety

### Positives 🟢
1. Clean extraction of export logic into ExportService — good separation of concerns

### New Patterns
ExportService introduces a new service class pattern for bulk data generation —
first usage in the codebase; worth adding a comment or ARCHITECTURE.md note.

### Pre-existing Audit Findings (from audit run 2 days ago)
[pre-existing] 🟡 app/serializers/node_serializer.rb — nil check missing for nil owners
(this is a separate issue, not introduced by this PR)
```

After the review, a Slack notification is sent to the team channel mentioning the PR author with the verdict summary.

## Guardrails

- **Author check** — blocks immediately if you try to review your own PR
- **Pre-existing audit findings** — surfaced as context only; do not affect the verdict
- **CI check** — CI status is always checked before deciding the verdict (CI still running → COMMENT, not APPROVE)
- **Stale thread escalation** — only triggers after 3+ follow-up runs with no author response (not on the first follow-up)

## Before / After

| | Run |
|---|---|
| Before | Be assigned to (or want to) review a colleague's PR |
| After: approved | Done — author can merge |
| After: requested changes | Author runs `respond <PR number>` |
| After: ran review before, new commits pushed | Run `review <PR number>` again — follow-up mode auto-detected |
