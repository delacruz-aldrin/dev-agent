# Mode: review

## Usage

```
/dev-agent review [PR link or number]
```

Reviews a colleague's PR — checks requirements coverage, logic, test coverage, BE/FE contract, and conventions. Leaves inline GitHub comments, submits a formal review verdict (APPROVE / REQUEST_CHANGES / COMMENT), and posts to Slack with a mention to the PR author.

**Only works on PRs you did NOT author.** Will redirect you to `respond` if it's your own PR.

Automatically detects whether this is a first review or a follow-up review based on prior comments.

**Examples:**
```
/dev-agent review 518
→ First review: reads diff + linked Jira ticket, leaves inline comments, submits verdict, notifies author on Slack

/dev-agent review 518   ← run again after author pushes updates
→ Follow-up mode: re-assesses only threads that were updated since the last review

/dev-agent review https://github.com/C-FO/baberu/pull/518
→ Same via full URL
```

---

## Phase 0 — Setup + Ownership Check
Read config.

Hard block — colleagues' PRs only:
- Fetch PR: `gh api repos/{REPO}/pulls/{pr_number}`
- Fetch authenticated user: `gh api user`
- If author = you: `⛔ This is your own PR. Use /dev-agent respond instead.`

Check for prior dev-agent review via `gh api repos/{REPO}/pulls/{pr_number}/reviews`:
- Reviews by authenticated user with inline comments → **Follow-up Mode**
- None found → **First Review Mode**
- Unsure → default to **First Review Mode**

### First Review Mode
Fetch PR diff, commits, description, additions/deletions, linked Jira ticket (Atlassian MCP), sample conventions.

**Size check:** `additions > 300` OR `deletions > 300` → assess split vs keep. Leave PR comment via `gh api repos/{REPO}/issues/{pr_number}/comments` either way. Proceed regardless.

### Follow-up Mode
Fetch all comments + replies. Identify files changed since prior review. Per thread:
- Replied + updated → re-assess change
- Replied + not updated → respond inline
- Not replied + updated → re-assess, note missing reply
- Not replied + not updated → flag outstanding, do not comment

If ALL threads = "not replied + not updated" → stop: "Nothing to follow up on yet."

## Phase 1 — XML
```xml
<prompt>
  <context>[Ticket summary, layers, PR scope]</context>
  <files>[Changed files by layer]</files>
  <conventions>[Sampled patterns]</conventions>
  <task>
    1. Changes satisfy Jira requirements?
    2. Consistent with existing conventions?
    3. Logic correct — edge cases, nil risks?
    4. Security vulnerabilities?
    5. Performance — N+1, missing indexes?
    6. ⚠️ TEST COVERAGE (highest priority — always 🔴 if missing):
       BE: every changed file covered? Happy/sad/edge cases? Behavior asserted not just execution?
       FE: changed components/services covered? TS interfaces match API shape?
    7. BE/FE contract: serializer/blueprint matches TS interfaces? Consuming code correct?
    8. PR description complete?
  </task>
  <constraints>
    - Jira requirements only. Blocking vs non-blocking. Exact file+line for every finding.
    - Do not approve if any blockers found.
    - Missing FE integration for a user-facing feature is 🔴 blocker.
    - BE/FE contract mismatch is 🔴 blocker.
  </constraints>
</prompt>
```

## Phase 2 — Execute
Classify findings: 🔴 Blocking / 🟡 Non-blocking / 🟢 Positive.

Leave inline comments via `gh api repos/{REPO}/pulls/{pr_number}/comments`.

**Check CI status** before deciding review verdict:
```bash
PR_SHA=$(gh api repos/{REPO}/pulls/{pr_number} --jq '.head.sha')
gh api repos/{REPO}/commits/{PR_SHA}/check-runs --jq '.check_runs[] | {name, status, conclusion}'
```
- All `conclusion = success` → CI passes
- Any `conclusion = failure` → CI fails
- Any `status != completed` → CI still running (treat as inconclusive)

Submit review via `gh api repos/{REPO}/pulls/{pr_number}/reviews`:
- `APPROVE` + "LGTM 🟢" — CI passes AND no blockers AND no suggestions
- `REQUEST_CHANGES` — any blockers present
- `COMMENT` — suggestions only, or CI not fully passed / inconclusive (state CI status explicitly)

Slack to `#{slack_channel}`: find thread via targeted text search in order — full URL → `{repo}/pull/{number}` → `pull/{number}` → PR title verbatim. Do NOT browse recent messages. Look up PR author Slack ID via Slack MCP. Reply with mention if found, new message if not. If Slack MCP fails: note in report and continue:
```
<@MEMBER_ID> [verdict] — [PR title]
[X] blocking, [Y] suggestions
```

```
## Review Report — [PR title]
### Verdict | ### Requirements Coverage
### Blocking Issues 🔴 | ### Suggestions 🟡 | ### Positives 🟢
### Convention Consistency | ### Logic | ### Security | ### Performance
### BE Test Coverage | ### FE Test Coverage | ### BE/FE Contract | ### PR Description
```
