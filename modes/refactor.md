# Mode: refactor

## Usage

```
/dev-agent refactor                          ← uses IDE selection if present
/dev-agent refactor <file>                   ← whole file
/dev-agent refactor <file>:<start>-<end>     ← specific line range
/dev-agent refactor "<description>"          ← plain description of the smell
/dev-agent refactor --from-audit <n>         ← finding number from last audit report
```

Restructures code for clarity, maintainability, or separation of concerns — without changing behavior. Runs a coverage gate before touching anything, shows a plan for approval, applies changes, runs the full test suite, and opens a PR.

**Examples:**
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

---

## Phase 0 — Setup

Read config. Run Backend Detection. Run Frontend Detection.

Switch to main:
```bash
git checkout {base_branch} && git pull origin {base_branch}
```
If checkout fails (uncommitted changes), stop:
```
⛔ Could not switch to {base_branch}. If you have uncommitted changes, stash (`git stash`) or commit them first. Otherwise check that {base_branch} exists and the remote is reachable.
```

**Resolve input — determine `REFACTOR_TARGET` and `ENTRY_HINT`:**

Check inputs in this order:

1. `--from-audit <n>` → resolve finding:
   - Read `.claude/dev-agent/context/_audit.json`. If present and `audited_at` is within 14 days: find the entry where `report_index == n`. Load its `file` and `summary` as `ENTRY_HINT`. Store the entry's `hash` as `RESOLVED_AUDIT_HASH` for use in Phase 4. If `escalated: true`: note in Session State as `[audit] finding #n was escalated (persisted {run_count} runs)`.
   - If `_audit.json` is absent or stale (>14 days): stop with: "Audit context is missing or expired. Run `/dev-agent audit` first to generate fresh findings." Do **not** fall back to `.claude/dev-agent-audit-state.json` — that file stores only hashes and run counts, not the file paths or summaries needed to resolve finding #n.
   - If `_audit.json` is fresh but has no entry with `report_index == n`: stop with: "Finding #n not found in the last audit (report had fewer than n findings). Run `/dev-agent audit` to refresh."
2. `<file>:<start>-<end>` → set `REFACTOR_TARGET=line_range`, `ENTRY_HINT=lines start–end of file`
3. `<file>` (no line range) → set `REFACTOR_TARGET=file`, `ENTRY_HINT=whole file`
4. `"<description>"` (quoted string, no file path) → set `REFACTOR_TARGET=description`, `ENTRY_HINT=description`
5. No argument + IDE selection present (check `<ide_selection>` in context) → set `REFACTOR_TARGET=selection`, `ENTRY_HINT=selected lines + their source file`
6. No argument + no selection → stop: "No target provided. Highlight code in your editor, pass a file path, or run with a description."

**Create branch** per **Shared: Create Branch** using prefix `refactor/` and a slug derived from the target:
- `--from-audit <n>` → `refactor/audit-<n>`
- file or line range → `refactor/<filename-slug>`
- description → `refactor/<short-slug>`
- selection → `refactor/<filename-slug>` (use the file containing the selection)

**Print Session State** before proceeding to Phase 1:
```
## Session State
BE_FRAMEWORK={value} | FRONTEND_ROOT={value} | STORE={value} | API_CLIENT={value}
REFACTOR_TARGET={value} | ENTRY_HINT={value} | BRANCH={value}
```

---

## Phase 1 — Scope Expansion & Coverage Gate

### Step 1 — Expand scope from entry hint

Treat `ENTRY_HINT` as the starting point — not the boundary. Read the target file(s). Identify:

- **`REFACTOR_SCOPE`** — the full set of files that will need to change: the source file(s) + any new files to extract to
- **`CALLER_SET`** — all callers/consumers of the methods, classes, or exports in scope

```bash
# Grep for all usages of the identified method/class/module names across the project
```

If any file in `CALLER_SET` is a third-party dependency (gem, node_module, vendor): exclude it from scope but note it in the report.

### Step 2 — Coverage gate

**If `BE_FRAMEWORK=none` AND `FE_TEST=none`:** skip this step entirely — no test infrastructure exists to check against. Note in Session State: `[coverage] skipped — no test infrastructure detected`.

For each file in `REFACTOR_SCOPE`, check whether a corresponding spec/test file exists:
- `rails`: `spec/**/*_spec.rb` matching the source path
- `express`/Node: `*.test.ts` or `*.spec.ts` co-located or in `__tests__/`
- `django`/`fastapi`: `test_*.py` or `*_test.py`
- `go`: `*_test.go` in the same package
- FE files (when `FE_TEST≠none`): apply the same pattern check using `FE_TEST_CMD`'s test file conventions

Flag any file without a matching test. If any flagged files exist, pause:

```
⚠️  The following files have no specs and are part of this refactor:
  - app/services/user_service.rb
  - app/controllers/user_controller.rb

Refactoring without tests risks silent regressions.
Write missing specs first? (yes / skip / abort)
```

- `yes` → write minimal coverage specs for each flagged file (happy path + key edge cases). Run `{BE_TEST_CMD}` to confirm they pass before continuing. If the file is FE-only, run `{FE_TEST_CMD}` instead.
- `skip` → note coverage gaps in report and continue
- `abort` → delete branch and stop

---

## Phase 2 — XML + Refactor Plan

```xml
<analysis>
  <context>[Stack, BE_FRAMEWORK, STORE, ENTRY_HINT, REFACTOR_SCOPE files, CALLER_SET]</context>
  <files>[Full content of REFACTOR_SCOPE files + relevant excerpts from CALLER_SET]</files>
  <task>
    1. What is the specific structural problem at the entry point?
    2. What is the minimal refactoring that resolves it without changing behavior?
    3. Which methods, classes, or modules will move, be extracted, or be renamed?
    4. Which callers in CALLER_SET are affected and how?
    5. Are any TS interfaces, API response shapes, or serializers affected?
  </task>
  <constraints>
    - Behavioral equivalence is non-negotiable. No logic changes — structure only.
    - Minimal scope: do not clean up code outside REFACTOR_SCOPE.
    - No new dependencies. No new patterns not already present in the codebase.
    - If a caller needs updating, include it in the plan — do not silently leave broken callers.
  </constraints>
</analysis>
```

After analysis, present a structured refactor plan and wait for approval:

```
## Refactor Plan

Entry point: app/services/user_service.rb:45-89
Problem: Validation logic mixed into service layer — 3 separate concerns in one class

Proposed changes:
  [NEW]     app/validators/user_validator.rb — extract validate_* methods (lines 45–67)
  [MODIFY]  app/services/user_service.rb — remove extracted methods, delegate to validator
  [MODIFY]  spec/services/user_service_spec.rb — update to reflect delegation

Callers affected: 2 (user_controller.rb, admin_controller.rb)
  → No signature changes — no caller edits needed

Proceed? (yes / adjust / abort)
```

- `yes` → continue to Phase 3
- `adjust` → ask what to change, revise plan, re-show, re-ask
- `abort` → revert branch and stop

**Out-of-scope findings:** if adjacent smells are found outside `REFACTOR_SCOPE`, surface them but never fix them inline:
```
Also found: [description] in [file] — out of scope for this refactor.
Create a follow-up Jira ticket? (yes / skip)
```

---

## Phase 3 — Execute

1. Apply all changes from the approved plan
2. Create any new files called for by the plan
3. Update all callers in `CALLER_SET` that require changes (import paths, renamed symbols, signature updates)
4. If TS interfaces are affected: update them
5. If `API_CLIENT=orval` and response shape changed: run `{API_GEN_CMD}` — skip if `API_GEN_CMD=none`, note in report
6. Update or create specs for every file in `REFACTOR_SCOPE`
7. Run **full** `{BE_TEST_CMD}` — not just specs for changed files (refactoring breaks distant callers):
   - Passes → continue
   - Fails → diagnose: broken caller (fix it and re-run) or unintended logic change (revert that part and re-plan)
   - Still failing → revert all changes, delete branch, note in report, stop
8. If `FE_TEST≠none`: run `{FE_TEST_CMD}`:
   - Passes → continue | Fails → fix + re-run | Still failing → revert FE changes, note in report, continue BE-only
9. Run **Shared: Run Quality Checks**
10. **Pre-commit review gate:** show a summary of all changed and created files with a brief description of each, then ask: "Ready to commit? (yes / review / revert all)"
    - `yes` → proceed
    - `review` → show full diff of each changed file, then re-ask
    - `revert all` → revert all changes, delete branch, stop
11. Commit and push:
    ```bash
    git add {every file changed or created}   # list files explicitly — never use git add . or git add -A
    git commit -m "refactor: [short description]"
    git push origin HEAD
    ```
12. Run **Shared: Create PR**. Use label `4.Quality improvement`. If invoked via `--from-audit <n>`: include the finding description and audit date in the PR body under a **Resolves Audit Finding** section.
13. **Audit state cleanup (only if invoked via `--from-audit <n>`):** after the PR is created, remove the resolved finding from both audit state files so the next audit run classifies it as `RESOLVED` rather than `PERSISTED`:
    - Read `.claude/dev-agent/context/_audit.json` — remove the entry with hash `{RESOLVED_AUDIT_HASH}`. Write back. If write fails: note in report and continue.
    - Read `.claude/dev-agent-audit-state.json` — remove `{RESOLVED_AUDIT_HASH}` from both `previous_hashes` and `run_counts`. Write back. If write fails: note in report and continue.

---

## Phase 4 — Report

```
## Refactor Report — [Target]
### Entry Point | ### Problem Identified | ### Changes Applied
### Callers Updated | ### Coverage | ### Test Suite | ### Out-of-Scope Findings | ### PR
```
