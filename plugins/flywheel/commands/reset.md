---
description: Reset flywheel state — three tiers (soft, config, full) to clear handoff log, reconfigure tools, or wipe everything
---

# Flywheel: Reset

You are resetting flywheel state for this project. Reset is **tiered** so users can clear just what they need without losing work that still matters. All destructive operations require explicit confirmation.

## Prerequisites

1. Check that `.flywheel/` exists. If not, tell the user flywheel isn't initialized here and stop.
2. Read `.flywheel/flywheel-config.json` and `.flywheel/feature-checklist.json` so you can show the user what exists before asking what to reset.
3. Read the last 5 entries of `.flywheel/claude-progress.jsonl` so you can show session history that would be cleared.

## Flow

Present the current state first, then ask the user which tier:

```
FLYWHEEL STATE — [project name]
┌──────────────────────────────────┬───────────────────────────┐
│ Config tools                     │ planning=…, review=…, …   │
│ Features                         │ N total (X done, Y pending)│
│ Handoff log                      │ N session entries         │
│ Feature branches (feat/*)        │ N local branches          │
│ Planning artifacts               │ task_plan.md, …           │
└──────────────────────────────────┴───────────────────────────┘

Reset tiers:
  1) Soft    — clear handoff log + reset feature statuses to pending
  2) Config  — soft reset + reset tool config (re-run /flywheel:init to reconfigure)
  3) Full    — delete .flywheel/ entirely (optional: delete feature branches + planning artifacts)
  4) Cancel
```

Always default to the safest option. Never run a tier without explicit user confirmation.

## Tier 1: Soft Reset

**Purpose**: Start a fresh relay cycle with the same features and tools. Useful after a major refactor or when the user wants to re-implement from scratch.

**Actions**:

1. Clear `.flywheel/claude-progress.jsonl` (truncate to empty file, do NOT delete — relay expects it to exist).
2. Remove `.flywheel/.relay-step` if present (stale breadcrumb).
3. In `.flywheel/feature-checklist.json`, for every feature:
   - Set `status` to `"pending"`
   - Set `completed_by_session` to `null`
   - Remove `blocked_reason` if present
   - Leave `title`, `priority`, `acceptance_criteria`, `dependencies`, `id` untouched
   - Do NOT touch features with `status: "split"` — the split is part of the checklist structure, not session state
4. Show the diff (before/after status summary) and ask for confirmation before writing.
5. After write, show the updated checklist table.

**Preserves**: Tool config, feature definitions, bootstrap scripts, git branches, source code.

## Tier 2: Config Reset

**Purpose**: User changed their stack (switched review tool, added a verification platform) and wants flywheel to re-detect and reconfigure without losing their feature list.

**Actions**:

1. Perform all Tier 1 actions (soft reset).
2. Delete `.flywheel/flywheel-config.json`.
3. Delete `.flywheel/init.sh` and `.flywheel/init.ps1` (they'll be regenerated at re-init based on current project state).
4. Tell the user: "Config cleared. Run `/flywheel:init` to reconfigure tools. Your feature list is preserved and will be re-used when init detects the existing `feature-checklist.json`."

**Preserves**: `feature-checklist.json` (content only, statuses reset), source code, git branches.

**Important**: When `/flywheel:init` runs after a Config Reset, it must detect the existing `feature-checklist.json` and offer to keep it instead of re-resolving the source. If the init command doesn't currently support this, warn the user that their feature list may be overwritten and ask whether to back it up first.

## Tier 3: Full Reset

**Purpose**: Project pivoted, epic complete, or user wants a clean slate.

**Actions**:

1. List everything that will be deleted:
   - `.flywheel/` directory (config, checklist, handoff log, bootstrap scripts)
   - Optionally: local git branches matching the pattern in `branch_naming` (default `feat/*`)
   - Optionally: planning artifacts in project root (`task_plan.md`, `findings.md`, `progress.md`, `proposal.md`, `specs/`)
2. Ask the user to confirm each optional group independently:
   - "Delete `.flywheel/` directory? (required for full reset)"
   - "Also delete N local feature branches? [list them]"
   - "Also delete planning artifacts? [list the files found]"
3. For branch deletion:
   - Only delete branches that are **fully merged** into the default branch OR that the user explicitly confirms as throwaway. Never use `git branch -D` without naming the exact branches and showing them to the user first.
   - Never delete the current branch. If the user is on a `feat/*` branch, tell them to switch to main first.
   - Never delete remote branches. Reset is a local operation.
4. For planning artifacts: only delete files that exist. Show the list before deletion.
5. After deletion, tell the user: "Full reset complete. Run `/flywheel:init` to start fresh."

**Preserves**: Project source code (everything outside `.flywheel/` and the listed planning artifacts), git history, git remote, `CLAUDE.md`, `README.md`.

## Rules

- **Confirmation is mandatory.** Every tier requires the user to explicitly confirm before any file is touched. Show the exact list of files/branches that will be modified or deleted.
- **Never touch source code.** Reset only affects `.flywheel/` artifacts, the feature checklist's session state, and (opt-in) feature branches and planning artifacts. Never delete files from `src/`, `tests/`, `docs/`, or anywhere outside the known artifact list.
- **Never push.** Reset is a local operation. Don't run `git push` or delete remote branches.
- **Never force-delete branches blindly.** Use `git branch -d` (safe delete, refuses unmerged) by default. Only escalate to `git branch -D` if the user explicitly confirms they want to discard unmerged work.
- **Keep `claude-progress.jsonl` existing in soft/config tiers.** The relay command expects this file to exist — truncate it to empty, don't delete.
- **No automatic commits.** Reset leaves changes staged only if the user asks. Let them review and commit (or not) themselves.
- **Validate JSON after edits.** After rewriting `feature-checklist.json` in a soft reset, re-read it to confirm valid JSON.
- **Stop on ambiguity.** If the user's intent is unclear ("reset" without specifying which tier), always ask — never pick a tier for them.
