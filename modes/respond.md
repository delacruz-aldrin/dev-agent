# Mode: respond

## Usage

```
/dev-agent respond [PR link or number]
```

Addresses all open review comments on your PR — applies valid changes, replies to invalid ones, re-runs tests, pushes, waits for CI, then re-requests review.

**Only works on PRs you authored.** Will hard-block if the PR belongs to someone else (use `review` for that).

**Examples:**
```
/dev-agent respond 519
→ Fetches unresolved threads on PR #519, applies valid suggestions, replies to the rest,
  pushes, polls CI for up to 15 min, then re-requests review from human reviewers

/dev-agent respond https://github.com/C-FO/baberu/pull/519
→ Same via full URL
```

**Typical flow after getting review comments:**
1. Reviewer leaves inline comments on your PR
2. Run `/dev-agent respond 519`
3. dev-agent handles all threads, pushes a new commit, and pings reviewers when CI is green

---

## Phase 0 — Setup + Ownership Check
Read config. Run Backend Detection. Run Frontend Detection.

Hard block — your PRs only:
- Fetch PR: `gh api repos/{REPO}/pulls/{pr_number}`
- Fetch authenticated user: `gh api user`
- If author ≠ you: `⛔ This PR was not authored by you. /dev-agent respond only works on your own PRs.`

Fetch unresolved threads only. If none: stop.

## Phase 1 — XML
```xml
<prompt>
  <context>[PR title, branch, author, thread count]</context>
  <comments>[Reviewer, file, line, body, suggestion per thread]</comments>
  <task>
    For each comment: assess validity → apply if valid → reply if not.
  </task>
  <constraints>
    - No changes conflicting with conventions, adding deps, or outside PR scope.
    - Replies: human, warm, occasionally humorous, varied tone. Never "As an AI".
    - Acknowledge valid changes genuinely. Decline with friendly explanation.
    - Partially valid: apply valid part, explain the rest.
  </constraints>
</prompt>
```

## Phase 2 — Execute
For each thread: assess → apply change or reply via `gh api repos/{REPO}/pulls/{pr_number}/comments/{id}/replies`.

After all threads:
1. Run `{BE_TEST_CMD}` — revert all changes if fails
2. Run **Shared: Run Quality Checks** — revert if lint/format still fails after auto-fix
3. Commit and push:
   ```bash
   git add {every file changed addressing comments}   # list files explicitly — never use git add . or git add -A
   git commit -m "chore: address PR review comments"
   git push origin HEAD
   ```
4. Wait for CI — poll with a 90-second interval, max 10 attempts (15 minutes total):
   ```bash
   SHA=$(git rev-parse HEAD)
   gh api repos/{REPO}/commits/{SHA}/check-runs --jq '.check_runs[] | {name, status, conclusion}'
   ```
   Repeat until all check runs have `status = completed`. Then assess conclusions:
   - All `conclusion = success` → **CI passes** → re-request review (human reviewers only, filter out `[bot]`) + `{pr_reviewer_team}` team
   - Any `conclusion = failure` → **CI fails** → note in report, post to Slack noting CI failure, do not re-request review
   - Still pending after 10 attempts → treat as CI inconclusive: note in report, do not re-request review
5. Transition Jira to "For Review" via Atlassian MCP — if fails: note in report and continue
6. Slack to `#{slack_channel}` — no mentions. Find thread via targeted text search in order: full URL → `{repo}/pull/{number}` → `pull/{number}` → PR title verbatim. Do NOT browse recent messages. Reply if found, new message if not:
   ```
   ✅ PR comments addressed — [PR title]
   PR: https://github.com/{REPO}/pull/{pr_number}
   [X] applied, [Y] declined
   ```
   If Slack MCP fails: note in report and continue.

```
## Respond Report — [PR title]
### Comments Addressed | ### Test Suite | ### Linting & Formatting
### CI Status | ### Re-review Requested | ### Jira Status
```
