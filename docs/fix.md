# fix

Diagnoses a bug, applies a scoped fix, runs tests, and opens a PR — all from a Jira ticket or a plain description.

## When to use

- You're assigned a bug ticket and want to get from ticket to PR in one command
- A bug was reported (in Slack, in Jira, verbally) and you want to fix it
- You want the fix done correctly: root cause traced, specs updated, side effects checked

## Usage

```
/dev-agent fix [Jira ticket key or URL]
/dev-agent fix [plain description of the bug]
```

**With a Jira ticket:**
```
/dev-agent fix HQA-37771
/dev-agent fix https://your-org.atlassian.net/browse/HQA-37771
```

**Without a ticket (manual):**
```
/dev-agent fix The page list table has wrong column widths when there are no pages
/dev-agent fix Login redirects to 404 after password reset
```

## What happens, step by step

### 1. Setup
- Reads your project config
- Checks out the base branch (`main`) and pulls latest
- Warns you if recent changes to `main` overlap with the area being fixed
- Creates a new branch: `bug/HQA-37771` (or `fix/manual-<slug>` for manual input)

### 2. Diagnosis
Traces the full code path from the symptom:
- **Backend:** route → controller → usecase/service → model → serializer
- **Frontend:** API hook → store/state → component

Reads pre-existing audit findings for any files in the trace path — surfaces them as context so known risks aren't missed.

Maps the symptom to the most likely bug location:

| Symptom | Focus |
|---|---|
| Duplicate data | Deduplication logic, unique constraints, race conditions |
| Slow / performance | N+1 queries, missing indexes, unnecessary re-renders |
| 500 errors / crashes | Nil checks, exception handling, edge cases |
| Wrong data displayed | Serialization, state management, field mapping |
| Auth / permission errors | Permission checks, session handling, route guards |
| UI / display bug | Component logic, conditional rendering, missing loading states |

### 3. Fix
- Applies the fix to backend and/or frontend files
- Updates TypeScript interfaces if the API response shape changed
- Creates or updates specs for every changed file

### 4. Side-effect check
If the fix touches a shared method (used by more than one controller/component), fix automatically checks all callers for unintended behavioral changes. At-risk callers get specs added. If a caller needs its own fix, that's applied too.

### 5. Pre-commit review gate
Before committing, fix shows you:
- A summary of every changed file and what was changed
- Options: `yes` (proceed), `review` (show full diff), `revert all` (abort cleanly)

### 6. PR + notifications
- Commits and pushes the branch
- Opens a PR with the project PR template, labels, milestone, and reviewer team
- Transitions the Jira ticket to "For Review"
- Posts a Slack thread to the team channel

## What you'll see

```
## Bug Report — GET /api/p/nodes/:id
### Root Cause
Nil check missing in NodeSerializer — `node.owner` returns nil for archived nodes
and the serializer calls `.email` unconditionally.

### Affected Files
Backend:
  - app/serializers/node_serializer.rb (fix applied)
  - spec/serializers/node_serializer_spec.rb (updated)

### Fix Applied
Added nil guard: `owner&.email` — returns null for archived nodes instead of 500-ing.

### Related Risks
  [audit] 🔴 app/serializers/user_serializer.rb — nil check missing for suspended users
  (pre-existing audit finding — not introduced by this fix)

### Test Suite  ✅ 142 examples, 0 failures
### PR  https://github.com/org/repo/pull/502
### Jira Status  HQA-37771 → For Review
```

## Guardrails

- **Won't start on dirty main** — requires a clean checkout of the base branch
- **Breaking-change warning** — warns if a `git pull` touched files in the trace path before you branch
- **Test failures block the commit** — if tests can't be fixed, all changes are reverted cleanly
- **Pre-commit gate** — you always see what's about to be committed before it is
- **Atlassian MCP check** — verifies Jira connectivity before starting (for ticket input); skipped for manual descriptions

## Before / After

| | Run |
|---|---|
| Before | Just have the ticket key or a description |
| After: PR looks right | merge it |
| After: reviewer rejects it | `refix HQA-37771 <PR number>` |
| After: unsure if fix is correct | `verify HQA-37771 <PR number>` |
| After: reviewer left comments | `respond <PR number>` |
