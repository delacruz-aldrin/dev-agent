# Mode: refix

## Usage

```
/dev-agent refix [Jira link or ticket key] [rejected PR link or number]
```

Re-diagnoses a bug after a fix was rejected or reverted, then opens a corrected PR.

**Both arguments are required.** Fetches the rejected PR diff and reviewer comments, classifies the rejection reason (`wrong_root_cause` or `side_effects`), and applies a corrected fix on a new branch with an incremented suffix (e.g. `bug/HQA-12345-2`).

**Examples:**
```
/dev-agent refix HQA-37771 501
→ Fetches PR #501 diff + review comments, re-diagnoses, opens bug/HQA-37771-2

/dev-agent refix HQA-37771 https://github.com/C-FO/baberu/pull/501
→ Same via full PR URL

/dev-agent refix MULTI-456 498
→ Works with any configured project key
```

---

## Phase 0 — Setup
Read config. Read context per **Shared: Session Context** — if stack is cached and the lockfile mtime is unchanged, skip Backend/Frontend Detection and use cached values; otherwise run Backend Detection and Frontend Detection. If `verify` key is present and `verify.pr_number` matches the rejected PR argument, set `VERIFY_CONTEXT_AVAILABLE=true` and store the verify findings.

**Atlassian MCP pre-flight:** fetch project metadata for `{jira_project}` via Atlassian MCP (cloudId = `{jira_domain}`). If it fails, stop immediately:
```
⛔ Atlassian MCP unreachable. Check authentication before continuing.
```

Switch to main:
```bash
git checkout main && git pull origin main
```
If checkout fails (uncommitted changes), stop:
```
⛔ Uncommitted changes detected. Stash (`git stash`) or commit before running /dev-agent refix.
```

Detect input — both are required. If either is missing, ask before continuing:
- **Jira ticket** (link or key) → fetch via Atlassian MCP (cloudId = `{jira_domain}`) — description, steps to reproduce, expected, actual, any updated acceptance criteria. Derive `TICKET_KEY` from URL or key.
- **Rejected PR** (GitHub PR link or number) → fetch via `gh pr view {number} --repo {REPO} --json title,body,comments,reviews,files` — diff, reviewer comments, and any CI failure details.

Create branch per **Shared: Create Branch**. Use the same `TICKET_KEY` with a `-2` suffix: e.g. `bug/HQA-12345-2`.
Check for branch collision before creating:
```bash
git branch --list "bug/{TICKET_KEY}-2" "feat/{TICKET_KEY}-2"
```
If the branch already exists, increment the suffix: try `-3`, `-4`, etc. until a free name is found. Use that name.

**Print Session State** before proceeding to Phase 1:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
TICKET_KEY={value} | BRANCH={value}
[context] verify findings loaded (verdict: NEEDS_DISCUSSION, N blocking)   ← only if VERIFY_CONTEXT_AVAILABLE=true
```

## Phase 1 — Rejection Autopsy

**If `VERIFY_CONTEXT_AVAILABLE=true`:** present the prior verify findings as the pre-filled rejection summary:
```
Prior verify found:
  Verdict: {verify.verdict}
  Blocking findings: {verify.blocking_findings}

Use these as the rejection basis? (yes / no, I'll describe it differently)
```
If yes: skip steps 1–4 below and go directly to the classification prompt, using the blocking findings to determine `REJECTION_TYPE`. If no: proceed with full autopsy.

**Otherwise:** analyze the rejected PR to reconstruct what was attempted and why it failed.

1. Read the full diff of the rejected PR: `gh pr diff {number} --repo {REPO}`
2. Extract all reviewer comments and requested changes
3. Check if any CI checks failed — note which and why
4. Fetch Jira ticket history and comments for any updated reproduction steps or changed acceptance criteria since the original fix

Produce a written **Rejection Summary**:
```
### What the previous fix did
[Describe the code change — which files, what logic was changed]

### Why it was rejected
[Reviewer comments / CI failures / production behavior — be specific]

### What was missed
[Edge cases, environment conditions, incorrect assumptions about root cause, or side effects introduced]
```

Classify the rejection using this structured prompt — do not ask as free text:
```
Based on the rejection summary, which best describes why the PR was rejected?

1. Wrong root cause — the fix addressed the wrong thing; the bug persisted or manifested differently
2. Side effects — the core fix was correct but introduced unintended behavior in other areas
3. Both — misdiagnosis AND side effects
4. Unclear — I'll describe it

Reply with 1, 2, 3, or 4 (and a description if 4).
```

Map response to `REJECTION_TYPE`:
- `1` → `wrong_root_cause`
- `2` → `side_effects`
- `3` → treat as `wrong_root_cause` for Phase 2 (re-diagnose from scratch), but also run Side Effect Map in Phase 2 as a separate step
- `4` → ask one follow-up clarifying question before proceeding

Do not proceed to Phase 2 until the summary and classification are complete.

## Phase 2 — Re-diagnosis

### If `REJECTION_TYPE=wrong_root_cause`

Trace the flow fresh using `BE_ARCH_TRACE`. Also trace frontend based on `STORE` (same as fix mode).

Read traced files only — do not rely on the previous fix's file selection.

```xml
<analysis>
  <context>[Stack, endpoint, layers, symptom]</context>
  <files>[Traced files only, line counts, patterns]</files>
  <previous_attempt>
    [What was changed, why it was rejected, what assumption was wrong]
  </previous_attempt>
  <task>
    [Symptom-specific questions — same as fix mode — but explicitly: what is the correct root cause
     that the previous fix did NOT address? What scenario or edge case was not covered?]
  </task>
  <constraints>
    - Traced flow only. No architectural changes. Minimal scoped fix.
    - The new diagnosis MUST differ meaningfully from the previous fix's approach.
    - Identify the exact bug location. Flag related risks.
    - Every scenario mentioned in the rejection must be covered by an explicit spec
      that fails before the fix and passes after.
    - If fix changes API response shape: update TS interfaces and consuming code.
  </constraints>
</analysis>
```

### If `REJECTION_TYPE=side_effects`

Do not re-diagnose the original bug — the core fix is correct. Instead, isolate the side effects:

1. Read the diff of the rejected PR again. Identify specifically which changed lines produced the unintended behavior (from reviewer comments or CI failures).
2. Grep for callers/consumers of those changed methods or exports across the codebase.
3. For each caller: determine whether the change altered behavior for it unexpectedly.
4. Produce a **Side Effect Map**:
   ```
   ### Changed: [method/class/export]
   ### Affected callers: [list with file paths]
   ### Unintended behavior: [what broke and why]
   ### Fix: [how to patch without disturbing the core fix]
   ```
5. Carry the core fix forward unchanged. Apply only targeted patches to the at-risk callers.
6. Cross-reference `_audit.json` per **Shared: Session Context** — apply recency gate (14 days) and overlap filter against the affected caller files from the Side Effect Map. If matches found: include them under **Related Risks** in the Phase 4 report labelled `[pre-existing audit finding]`. Skip this step for `REJECTION_TYPE=wrong_root_cause` — the new trace may touch different files entirely.

## Phase 3 — Execute

1. Apply fix to files (BE and FE as needed)
   - If `REJECTION_TYPE=side_effects`: preserve the original core fix diff; apply only side-effect patches on top
   - If `REJECTION_TYPE=both` (treated as `wrong_root_cause` in Phase 2): apply the fresh re-diagnosis fix AND the side-effect patches from the Side Effect Map produced in Phase 2
2. Update TS interfaces if API response shape changed
3. If `API_CLIENT=orval` and shape changed: run `{API_GEN_CMD}`
4. Update frontend consuming code (hooks/service/state/component) if affected
5. Create/update specs for every changed BE file — with special attention to:
   - The exact scenario from the rejection (must fail before fix, pass after)
   - Any edge cases or conditions mentioned by reviewers
   - If `REJECTION_TYPE=side_effects`: every at-risk caller from the Side Effect Map must have a spec
6. Run `{BE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert all changes, note in report, stop
7. If `FE_TEST≠none`: run `{FE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert FE changes, note in report, continue with BE-only
8. **Side-effect check** — skip if `REJECTION_TYPE=side_effects` OR `REJECTION_TYPE=both` (Phase 2 already produced a complete Side Effect Map that covers this). Run only if `REJECTION_TYPE=wrong_root_cause`:
   Trigger if any changed file is a shared interactor, model method, service, serializer/blueprint, or shared frontend hook/store/utility.
   If triggered: grep callers, read each, flag at-risk ones, add specs, fix if needed, re-run `{BE_TEST_CMD}`.
9. Run **Shared: Run Quality Checks**
10. Commit and push:
    ```bash
    git add {every file changed in this refix}   # list files explicitly — never use git add . or git add -A
    git commit -m "fix: [short description]"
    git push origin HEAD
    ```

## Phase 4 — Report & PR

1. Run **Shared: Create PR** with `TICKET_KEY`. Pass the Jira ticket URL as the ticket link.
   - The filled PR body **must also include** (append after the template sections):
     - "Supersedes #{rejected_pr_number}"
     - If `REJECTION_TYPE=wrong_root_cause`: a "Why the previous fix was wrong" section explaining the misdiagnosis
     - If `REJECTION_TYPE=side_effects`: a "What the side effects were and how they were addressed" section, confirming the core fix is unchanged
     - Updated test cases checklist covering the rejection scenario
2. Transition Jira back to "For Review" via Atlassian MCP — if fails: note in report and continue
3. Run **Shared: Post Slack Thread**
4. **Auto-verify offer:** ask: "Run `/dev-agent verify` on the new PR to confirm the corrected diagnosis holds? (yes/no)". If yes, run verify inline with `--comment` so findings are posted directly to the PR.
5. Write context per **Shared: Session Context** — increment `refix_count`; clear `fix` and `verify` keys (new fix attempt, old findings no longer valid).

```
## Refix Report — [Endpoint]
### Rejection Summary | ### Root Cause (Corrected) | ### Affected Files (BE + FE)
### Fix Applied | ### Rejection Scenario Coverage | ### Test Suite | ### Jira Status | ### PR
```
