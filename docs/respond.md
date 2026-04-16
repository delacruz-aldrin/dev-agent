# respond

Addresses all open review comments on your PR — applies changes, replies to invalid ones, runs tests, pushes, and re-requests review.

## When to use

- You got review comments on your PR and want them handled systematically
- A reviewer left GitHub Suggestions you want applied automatically
- You want tests re-run and CI polled before pinging reviewers again

## Usage

```
/dev-agent respond [PR number or URL]
```

```
/dev-agent respond 519
/dev-agent respond https://github.com/org/repo/pull/519
```

**Only works on PRs you authored.** If you try to run it on someone else's PR, it will redirect you to `review`.

## What happens, step by step

### 1. Setup
- Reads your project config and detects the stack
- Fetches the PR and verifies you are the author
- Loads the linked Jira ticket (if the PR body contains a Jira link) for requirements context
- Checks pre-existing audit findings for files changed in the PR — surfaces them as context

If there are no open review threads: stops immediately (nothing to do).

### 2. Comment triage

For each open review thread, respond decides:

**Valid comments** — applied as code changes:
- Fixes a genuine bug or regression
- Aligns with existing conventions
- Is within the PR's scope
- Addresses a requirement from the Jira ticket

**Invalid comments** — replied to with a friendly explanation:
- Contradicts the Jira acceptance criteria
- Introduces new dependencies
- Is out of scope for this PR
- Partially valid: the valid part is applied, the rest is explained

**GitHub Suggestions** — applied directly to the file, not just acknowledged. The suggested lines are written exactly, then committed.

### 3. Pre-push review gate

Before pushing, respond shows you a table of every file changed and the type of change (applied suggestion / manual edit). Options: `yes` (push), `review changes` (see full diff), `revert all` (abort cleanly).

### 4. Tests, CI, and re-review

After pushing:
1. Runs backend tests — reverts all changes if they fail
2. Runs frontend tests (if applicable) — reverts FE changes if they fail
3. Polls required CI checks (up to 15 minutes, every 90 seconds)
4. When CI passes: re-requests review from all human reviewers + the reviewer team
5. Posts a Slack update to the PR thread: `✅ PR comments addressed — [PR title]`
6. If CI fails: posts Slack noting the failure, does not re-request review

### 5. Jira
If the PR is linked to a Jira ticket, transitions it back to "For Review".

## What you'll see

```
## Respond Report — Add node export endpoint (PR #519)

### Comments Addressed
| Thread | Reviewer | Action |
|--------|----------|--------|
| node_serializer.rb:43 | @alice | Applied suggestion — added .presence check |
| nodes_controller.rb:12 | @bob | Applied — extracted to private method |
| spec/nodes_controller_spec.rb | @alice | Replied — this is covered by integration tests per the ticket |

### Test Suite  ✅ 145 examples, 0 failures
### CI Status  ✅ All required checks passed
### Re-review Requested  @alice, @bob, @team-reviewers

### Pre-existing Audit Findings (from audit run 4 days ago)
[pre-existing] 🟡 app/serializers/node_serializer.rb — nil check missing for nil owners
(surfaced for context — not introduced by this PR)
```

## Guardrails

- **Author check** — blocks immediately if the PR isn't yours
- **GitHub Suggestion handling** — suggestions are applied as actual file edits, not just GitHub acknowledgements
- **Jira requirement awareness** — uses the linked ticket's acceptance criteria to evaluate whether a comment is valid
- **CI timeout** — polls for up to 15 minutes; reports CI as inconclusive after that rather than blocking indefinitely
- **Pre-existing audit findings** — shown as context only, don't affect how comments are handled

## Before / After

| | Run |
|---|---|
| Before | Reviewer has left comments or suggestions on your PR |
| After: CI passes, re-review requested | Wait for another review round |
| After: reviewer approves | Merge |
| After: reviewer still rejects core approach | `refix <ticket> <PR number>` |
