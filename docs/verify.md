# verify

Independent pre-merge check — traces the code path from scratch and compares it against what the PR actually changed. Returns a clear verdict.

## When to use

- Before merging a PR you're not 100% confident about
- After a `refix` — to confirm the corrected approach actually holds
- When you want a second opinion on a PR that looks right but feels off
- As a reviewer who wants a structured risk assessment before approving
- QA wanting to understand whether a PR covers what it claims

## Usage

```
/dev-agent verify [Jira ticket] [PR number or URL]
/dev-agent verify [Jira ticket] [PR number or URL] --comment
```

```
/dev-agent verify HQA-37771 519
/dev-agent verify HQA-37771 https://github.com/org/repo/pull/519
/dev-agent verify HQA-37771 519 --comment
```

**`--comment`** — posts the full verify report as a GitHub review comment on the PR, so reviewers can see it inline. Without `--comment`, the report is printed locally only.

Both ticket and PR arguments are required.

## What it checks

verify works in read-only mode. It never modifies files, never commits, never pushes.

It independently traces the affected code path — **ignoring the PR diff** — then compares what it found against what the PR actually changed:

| Check | What it looks for |
|---|---|
| **Root cause assessment** | Does the PR fix the actual root cause, or just mask the symptom? |
| **BE trace gaps** | Files that should have been changed on the backend but weren't |
| **FE trace gaps** | Files that should have been changed on the frontend but weren't |
| **BE/FE contract** | Does the API response shape match the TypeScript interfaces? |
| **Frontend consuming code** | Was the frontend updated to use the new API shape? |
| **Spec coverage (BE)** | Were tests added or updated for every changed file? |
| **Test coverage (FE)** | Were frontend tests added or updated? |
| **New risks introduced** | Does the PR introduce new risks in areas it touches? |
| **Convention consistency** | Does the PR follow existing patterns? |
| **Pre-existing audit findings** | Are there known risks in the changed files from a prior audit? |

### Pre-existing audit findings

If an `audit` was run in the last 14 days, verify checks whether any audit findings overlap with the PR's changed files. These appear in a **separate section** — clearly labelled as pre-existing, not introduced by the PR — and **do not affect the verdict**. They're surfaced so the reviewer has full context.

### Delta comparison

If verify was run on this PR before, the new report shows what changed since last time:
- **NEW** findings (appeared since last verify)
- **RESOLVED** findings (fixed since last verify)
- **PERSISTED** findings (still present)

## Verdicts

```
SAFE TO MERGE     — no blocking findings
DO NOT MERGE      — one or more blocking findings
NEEDS DISCUSSION  — no blockers, but non-trivial suggestions or ambiguous risks
```

Findings are classified as:
- 🔴 **Blocking** — would cause a bug, regression, or security issue in production
- 🟡 **Non-blocking** — suboptimal but not a correctness issue
- 🟢 **Positive** — worth calling out

## What you'll see

```
## Verify Report — HQA-37771 / PR #519

### Verdict: DO NOT MERGE

### Delta: 2 new findings | 0 resolved | 1 persisted

### Root Cause Assessment
The PR correctly identifies the nil check in NodeSerializer as the root cause.
Fix at line 43 is appropriate.

### PR vs Live Trace (BE)
Gap: NodeQuery#for_export also passes archived nodes with nil owners to the serializer.
The PR fixes the serializer but not the query — the same 500 can still occur via the export path.

### Spec Coverage (BE)
❌ spec/serializers/node_serializer_spec.rb — no test for archived node case added

### Pre-existing Audit Findings (from audit run 3 days ago)
[pre-existing audit finding] 🔴 app/serializers/user_serializer.rb
    Similar nil check missing for suspended users — separate issue, not introduced by this PR

### Findings
| # | Severity | Finding |
|---|----------|---------|
| 1 | 🔴 Blocking | Export path not covered — NodeQuery#for_export still passes nil owners |
| 2 | 🔴 Blocking | No spec for archived node scenario in node_serializer_spec.rb |
| 3 | 🟡 Non-blocking | Nil guard uses `.&email` — consider `.email.presence` for consistency |
```

## Guardrails

- Completely read-only — no files are changed, no commits, no pushes
- Pre-existing audit findings never affect the verdict — they're informational only
- Won't start if the Jira ticket key doesn't exist in your project
- `--comment` requires GitHub access (via `gh` CLI)

## Before / After

| | Run |
|---|---|
| Before | Have the ticket key and PR number |
| After: SAFE TO MERGE | Merge the PR |
| After: DO NOT MERGE | `refix <ticket> <PR number>` — refix loads verify's findings automatically |
| After: NEEDS DISCUSSION | Share the report with the team, discuss, then decide |
