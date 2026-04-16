# refix

Re-diagnoses a bug after a fix was rejected or reverted, then opens a corrected PR on a new branch.

## When to use

- A PR you opened with `fix` was rejected by a reviewer
- A deployed fix was reverted (it broke something in production)
- You got a "DO NOT MERGE" from `verify` and need to address the findings
- A second attempt is needed with a different approach

## Usage

```
/dev-agent refix [Jira ticket] [rejected PR number or URL]
```

Both arguments are required.

```
/dev-agent refix HQA-37771 501
/dev-agent refix HQA-37771 https://github.com/org/repo/pull/501
```

The new branch will be created with an incremented suffix:
- First fix: `bug/HQA-37771`
- First refix: `bug/HQA-37771-2`
- Second refix: `bug/HQA-37771-3`

## What it does differently from fix

refix doesn't just re-run fix. It first performs a **rejection autopsy** — a structured analysis of what went wrong — before touching any code.

### Step 1 — Rejection autopsy

refix reads:
- The full diff of the rejected PR
- All reviewer comments and requested changes
- Any CI failures
- The Jira ticket history (in case acceptance criteria changed after the original fix)

It produces a written summary:
- What the previous fix changed
- Why it was rejected
- What was missed or assumed incorrectly

### Step 2 — Rejection classification

You're asked to classify the rejection (or it's inferred from context):

| Type | Meaning |
|---|---|
| **Wrong root cause** | The fix addressed the wrong thing; the bug still exists or manifested differently |
| **Side effects** | The fix itself was correct, but it broke something else |
| **Both** | Misdiagnosis AND introduced side effects |

If `verify` was run on the rejected PR, refix loads those findings automatically — you don't have to describe the rejection from scratch.

### Step 3 — Re-diagnosis (based on rejection type)

**Wrong root cause:** traces the code path fresh, as if starting over. The previous approach is explicitly excluded — the new diagnosis must differ meaningfully. Every scenario mentioned in the rejection must have a spec that fails before the fix and passes after.

**Side effects:** the core fix is preserved unchanged. Instead, refix maps every caller affected by the changed code, identifies which ones broke, and applies targeted patches — without disturbing the original fix.

**Both:** performs the full wrong-root-cause re-diagnosis, then runs the side-effect mapping on top.

For side-effect rejections, refix also cross-references pre-existing audit findings in the affected caller files — surfacing known risks that may have contributed.

### Step 4 — PR

The new PR body automatically includes:
- "Supersedes #501" (links to the rejected PR)
- A "Why the previous fix was wrong" section (for wrong root cause)
- A "What the side effects were and how they were addressed" section (for side effects)
- An updated test cases checklist covering the rejection scenario

After the PR is created, refix offers to run `verify` inline on the new PR to confirm the corrected approach holds before asking anyone to review it.

## What you'll see

```
## Refix Report — GET /api/p/nodes/:id

### Rejection Summary
Previous fix added a nil guard at the serializer level.
Rejected because: the nil case originates in the query — the serializer nil-guard
hid the root cause without fixing it, and broke archived node exports.

### Root Cause (Corrected)
NodeQuery#for_display filters out archived nodes but NodeQuery#for_export does not.
The export path passes archived nodes to the serializer with a nil owner.
Fix: add explicit owner presence check in NodeQuery#for_export.

### Rejection Scenario Coverage
✅ Export with archived node — now returns empty owner instead of 500-ing
✅ Display with archived node — unaffected (query filter preserved)

### Test Suite  ✅ 145 examples, 0 failures
### PR  https://github.com/org/repo/pull/508 (supersedes #501)
### Jira Status  HQA-37771 → For Review
```

## Guardrails

- Both arguments (ticket + rejected PR) must be provided — refix won't guess
- Rejection classification is structured (numbered choices, not free text) to avoid ambiguity
- Side-effect patches are always isolated — the core fix is never modified when the rejection type is `side_effects`
- Context from `verify` is loaded automatically if you ran it before — no re-description needed

## Before / After

| | Run |
|---|---|
| Before | Have the ticket key and the rejected PR number |
| After: new PR looks right | Let reviewers know and wait for review |
| After: still unsure | `verify HQA-37771 <new PR number>` |
| After: reviewer left comments on new PR | `respond <new PR number>` |
