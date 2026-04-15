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
Read config. Read context per **Shared: Session Context** — if stack is cached and the lockfile mtime is unchanged, skip Backend/Frontend Detection and use cached values; otherwise run Backend Detection and Frontend Detection.

Hard block — your PRs only:
- Fetch PR: `gh api repos/{REPO}/pulls/{pr_number}`
- Fetch authenticated user: `gh api user`
- If author ≠ you: `⛔ This PR was not authored by you. /dev-agent respond only works on your own PRs.`

Fetch unresolved threads only. If none: stop.

Fetch linked Jira ticket for context: scan the PR body for a Jira URL matching `{jira_domain}`. If found:
- **Atlassian MCP pre-flight:** fetch project metadata for `{jira_project}` via Atlassian MCP (cloudId = `{jira_domain}`). If it fails: set `JIRA_REQUIREMENTS=none` and log a warning — do not stop the mode entirely (unlike Jira-required modes, Jira context is supplementary here).
- If pre-flight passes: fetch the ticket — description and acceptance criteria. Store as `JIRA_REQUIREMENTS`.
- If not found in PR body: `JIRA_REQUIREMENTS=none`.

Read `_audit.json` per **Shared: Session Context** — apply recency gate (14 days) and overlap filter against the PR's changed files. Store matching findings as `RESPOND_AUDIT_FINDINGS`. These are pre-existing risks, not introduced by the PR — they inform responses but do not affect how comments are addressed.

**Print Session State** before proceeding to Phase 1:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
PR_NUMBER={value} | JIRA_REQUIREMENTS={found/none}
[context] N pre-existing audit finding(s) in changed files   ← only if RESPOND_AUDIT_FINDINGS non-empty
```

## Phase 1 — XML
```xml
<analysis>
  <context>[PR title, branch, author, thread count]</context>
  <requirements>[Jira acceptance criteria if JIRA_REQUIREMENTS≠none; omit block if none]</requirements>
  <comments>[Reviewer, file, line, body, suggestion per thread]</comments>
  <task>
    For each comment: assess validity → apply if valid → reply if not.
    A comment is valid if it: (a) fixes a genuine bug or regression, (b) aligns with existing conventions,
    (c) is within PR scope, or (d) addresses a requirement from JIRA_REQUIREMENTS.
    A comment is invalid if it: contradicts the Jira acceptance criteria, introduces new deps, or is out of scope.
  </task>
  <constraints>
    - No changes conflicting with conventions, adding deps, or outside PR scope.
    - Replies: human, warm, occasionally humorous, varied tone. Never "As an AI".
    - Acknowledge valid changes genuinely. Decline with friendly explanation.
    - Partially valid: apply valid part, explain the rest.
  </constraints>
</analysis>
```

## Phase 2 — Execute
For each thread:
- Detect if the comment body contains a GitHub suggestion block (` ```suggestion ` fence). If yes: apply the suggested change by editing the file directly — extract the suggested lines from the suggestion block and write them to the file at the indicated path and line range. Do not use the GitHub reviews POST endpoint for this — that creates a comment, it does not apply the code change. After editing the file, the change will be included in the commit at step 4.
- For all other comments: assess validity → apply change or reply via `gh api repos/{REPO}/pulls/{pr_number}/comments/{id}/replies`.

After all threads:
1. Run `{BE_TEST_CMD}` — revert all changes if fails
2. If `FE_TEST≠none` and any frontend files were changed: run `{FE_TEST_CMD}` — if tests fail after auto-fix: revert FE changes, note in report, continue with BE-only response
3. Run **Shared: Run Quality Checks** — revert if lint/format still fails after auto-fix
4. **Pre-push review gate:** show a table of all files changed and the type of change (applied suggestion / manual edit), then ask: "Push these changes and re-request review? (yes / review changes / revert all)".
   - `yes` → proceed
   - `review changes` → show full diff, then re-ask
   - `revert all` → revert all changes, note in report, stop
5. Commit and push:
   ```bash
   git add {every file changed addressing comments}   # list files explicitly — never use git add . or git add -A
   git commit -m "chore: address PR review comments"
   git push origin HEAD
   ```
6. Wait for CI — first fetch required status checks from branch protection to avoid polling unrelated checks (deploy previews, bots, coverage reporters):
   ```bash
   REQUIRED=$(gh api repos/{REPO}/branches/{base_branch}/protection --jq '.required_status_checks.contexts[]' 2>/dev/null)
   ```
   If branch protection is not configured or returns empty, fall back to polling all check runs. Poll with a 90-second interval, max 10 attempts (15 minutes total):
   ```bash
   SHA=$(git rev-parse HEAD)
   gh api repos/{REPO}/commits/{SHA}/check-runs --jq '.check_runs[] | select(.name as $n | $REQUIRED | index($n)) | {name, status, conclusion}'
   ```
   Repeat until all required check runs have `status = completed`. Then assess conclusions:
   - All `conclusion = success` → **CI passes** → re-request review (human reviewers only, filter out `[bot]`) + `{pr_reviewer_team}` team
   - Any `conclusion = failure` → **CI fails** → note in report, post to Slack noting CI failure, do not re-request review
   - Still pending after 10 attempts → treat as CI inconclusive: note in report, do not re-request review
6. Transition Jira to "For Review" via Atlassian MCP — if fails: note in report and continue
7. Slack to `#{slack_channel}` — no mentions. Find thread via targeted text search in order: full URL (raw) → full URL wrapped as `<https://...>` → `{repo}/pull/{number}` → `pull/{number}` → PR title verbatim. Do NOT browse recent messages. Reply if found, new message if not:
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
### Pre-existing Audit Findings (omit section if RESPOND_AUDIT_FINDINGS empty)
```
