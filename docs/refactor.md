# refactor

Restructures existing code for clarity or maintainability — without changing how it behaves. Runs a coverage gate first, shows a plan for your approval, applies changes, and opens a PR.

## When to use

- A file or function has grown too complex and needs splitting up
- You spotted a structural problem in code that's otherwise working
- An `audit` finding points to a file that needs structural cleanup
- You highlighted code in your editor and want a refactor proposal
- You're paying down tech debt before adding new features on top

**What refactor will NOT do:**
- Change logic or fix bugs
- Add new features
- Touch code outside the identified scope

## Usage

```
/dev-agent refactor                          ← uses IDE selection (code highlighted in editor)
/dev-agent refactor <file>                   ← whole file
/dev-agent refactor <file>:<start>-<end>     ← specific line range
/dev-agent refactor "<description>"          ← plain description of the problem
/dev-agent refactor --from-audit <n>         ← finding number from last audit report
```

```
/dev-agent refactor
→ Uses highlighted IDE selection as the starting point

/dev-agent refactor app/services/user_service.rb:45-89
→ Treats lines 45–89 as the entry point; expands scope to find callers

/dev-agent refactor app/services/user_service.rb
→ Scans the whole file for structural issues

/dev-agent refactor "extract validation logic out of UserController"
→ Locates the relevant code and plans the extraction

/dev-agent refactor --from-audit 3
→ Loads finding #3 from the last audit report and refactors it
```

## What happens

### 1. Setup and input resolution

Refactor checks out the base branch and identifies the entry point from your input — whether that's a highlighted selection, file, line range, description, or audit finding.

For `--from-audit <n>`: reads the audit context file and loads the specific finding by its report number. The finding must be from an audit run in the last 14 days.

### 2. Scope expansion

The entry point is a **starting point**, not a boundary. Refactor expands the scope:

- **Refactor scope** — the files that need to change (source file + any new files to extract to)
- **Caller set** — all callers and consumers of the methods, classes, or exports being changed

This ensures broken callers aren't silently left behind.

### 3. Coverage gate

Before touching any code, refactor checks whether every file in the refactor scope has tests.

If a file has no tests, you're asked:

```
⚠️ The following files have no specs and are part of this refactor:
  - app/services/user_service.rb

Refactoring without tests risks silent regressions.
Write missing specs first? (yes / skip / abort)
```

- `yes` → minimal specs are written and run before the refactor starts
- `skip` → noted in the report; refactor continues with known coverage gaps
- `abort` → clean exit, no changes made

### 4. Plan shown for approval

After analysis, a structured refactor plan is presented — **you must approve it before anything changes**:

```
## Refactor Plan

Entry point: app/services/user_service.rb:45-89
Problem: Validation logic mixed into service layer — 3 concerns in one class

Proposed changes:
  [NEW]     app/validators/user_validator.rb — extract validate_* methods (lines 45–67)
  [MODIFY]  app/services/user_service.rb — remove extracted methods, delegate to validator
  [MODIFY]  spec/services/user_service_spec.rb — update to reflect delegation

Callers affected: 2 (user_controller.rb, admin_controller.rb)
  → No signature changes — no caller edits needed

Proceed? (yes / adjust / abort)
```

Options:
- `yes` → proceed
- `adjust` → describe what to change; the plan is revised and re-shown
- `abort` → clean exit, branch deleted

### 5. Execute

Applies all changes from the approved plan:
- Creates new files (e.g., extracted classes)
- Modifies source files
- Updates all affected callers
- Updates TypeScript interfaces if needed
- Updates or creates specs for every changed file
- Runs the **full** test suite (not just specs for changed files — refactoring can break distant callers)

### 6. Pre-commit review gate

Shows a summary of all changes before committing. Options: `yes`, `review` (full diff), `revert all`.

### 7. PR

Opens a PR with the `4.Quality improvement` label.

For `--from-audit <n>`: the PR body includes the original audit finding and its date under a **Resolves Audit Finding** section. After the PR is created, the finding is removed from the audit state — the next `audit` run will classify it as **RESOLVED** instead of persisted.

## Out-of-scope findings

If adjacent code smells are found outside the refactor scope, they're surfaced but never fixed inline:

```
Also found: [description] in [file] — out of scope for this refactor.
Create a follow-up Jira ticket? (yes / skip)
```

## What you'll see

```
## Refactor Report — app/services/user_service.rb:45-89

### Problem Identified
Validation logic (validate_email, validate_role, validate_quota) mixed into the service layer.
Three separate concerns in one class — makes the service hard to test and extend.

### Changes Applied
  [NEW]     app/validators/user_validator.rb
  [MODIFY]  app/services/user_service.rb (removed validate_* methods, delegated to validator)
  [MODIFY]  spec/services/user_service_spec.rb

### Callers Updated
  No signature changes — no caller edits needed

### Coverage
All files in refactor scope had existing specs.

### Test Suite  ✅ 152 examples, 0 failures

### PR  https://github.com/org/repo/pull/520
       Label: 4.Quality improvement
```

## Guardrails

- **Behavioral equivalence is enforced** — refactor applies structural changes only; any logic change is a sign something went wrong and is flagged
- **Plan approval required** — nothing is written until you approve the plan
- **Coverage gate** — warns before touching untested code
- **Full test suite after** — not just the changed files; catches distant callers broken by the restructuring
- **Caller scope included** — callers that need updating are always part of the plan, never silently left broken
- **Audit state cleanup** — if refactoring a `--from-audit` finding, the finding is removed from audit state so future runs see it as resolved

## Before / After

| | Run |
|---|---|
| Before | Identify the entry point (file, lines, selection, description, or audit finding number) |
| After: PR opened | Wait for review |
| After: want to combine with a bug fix | Do them separately — don't mix refactor commits with logic changes |
