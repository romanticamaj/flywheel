---
description: Re-detect installed tools and update flywheel-config.json non-destructively — preserves checklist, handoff log, and init scripts
---

# Flywheel: Retool

You are updating tool configuration for an existing flywheel project. The user has installed (or removed) tools since `/flywheel:init` ran, and wants the config to reflect what's actually available.

**REQUIRED:** Read the `flywheel:hub` skill first for the config schema reference, then follow the protocol below.

## Prerequisites

The project must already be initialized — `.flywheel/flywheel-config.json` must exist. If it doesn't, tell the user to run `/flywheel:init` first and exit.

## Critical Rules

1. **PRESERVE the existing config schema.** Do not invent new top-level keys. The config keeps these top-level keys: `planning`, `implementation` (if present), `multi_agent`, `profile`, `review`, `verification`, `source`, `scope_rule`, `exit_rule`, `branch_naming`.
2. **Each spoke keeps `tool` (string) and `alternatives` (array) fields.** Only the values inside may change.
3. **Non-destructive.** Only `.flywheel/flywheel-config.json` may be modified. Do NOT touch:
   - `.flywheel/feature-checklist.json`
   - `.flywheel/claude-progress.jsonl`
   - `.flywheel/init.sh` or `.flywheel/init.ps1`
4. **Show a diff before writing.** The user sees what will change and can cancel.

## Protocol

### Step 1: Read Current Config

Read `.flywheel/flywheel-config.json` and note its exact top-level structure. Capture the currently-configured tool for each spoke.

### Step 2: Re-Detect Available Tools

Run the same detection algorithm as the initializer (see `initializer-template.md` Section 1 "Runtime Detection"):

- **Planning:** check skills list for `planning-with-files`, `superpowers:writing-plans`, `openspec`
- **Implementation:** check skills list for `superpowers:test-driven-development`, `superpowers:incremental-implementation`, `superpowers:systematic-debugging`
- **Multi-agent:** check skills list for `superpowers:dispatching-parallel-agents`, `superpowers:subagent-driven-development`, `gstack`
- **Cleanup:** check for `simplify`, `superpowers:simplify`
- **Peer review:** check for `coderabbit:code-review`, `code-review:code-review`, `superpowers:requesting-code-review`, `gstack:/review`
- **Cross-model:** check for `codex:review`, `codex:rescue`, `gstack:/codex`, `gemini` (CLI in PATH)
- **E2E (review):** check for `mcp__plugin_playwright_*`, `gstack:/qa`
- **Verification platforms:** check MCP tools/CLIs for each configured platform

### Step 3: Compute Diff

For each spoke in the existing config, compare what's now detected vs what's configured:

```
TOOL DETECTION DIFF
┌──────────────────┬──────────────────────┬──────────────────────┬───────────┐
│ Spoke            │ Currently configured │ Newly detected       │ Action    │
├──────────────────┼──────────────────────┼──────────────────────┼───────────┤
│ planning         │ built-in             │ planning-with-files  │ ⬆ upgrade │
│ implementation   │ built-in             │ superpowers:tdd      │ ⬆ upgrade │
│ peer-review      │ superpowers:peer-rev │ (not found)          │ ⬇ fallback│
│ cross-model      │ codex:review         │ codex:review         │ ✓ same    │
│ e2e              │ built-in             │ playwright           │ ⬆ upgrade │
└──────────────────┴──────────────────────┴──────────────────────┴───────────┘
```

**Action legend:**
- `✓ same` — tool is still installed, no change
- `⬆ upgrade` — a better-ranked tool is now available
- `⬇ fallback` — currently configured tool is missing, will fall back to `built-in` or next alternative
- `+ alternative` — newly detected tool added to `alternatives` array (configured tool unchanged)

### Step 4: Confirm with User

Present the diff and ask:

```
Apply these changes to .flywheel/flywheel-config.json?
  Y) Yes — write changes and commit
  N) No  — cancel, leave config unchanged
  E) Edit — review which spokes to update one by one
```

If user picks **E**, walk through each upgrade/fallback and ask per-spoke.

### Step 5: Write Updated Config

If user approves, write the updated config back. Preserve the schema EXACTLY:

```json
{
  "planning": { "tool": "<updated>", "alternatives": ["<existing+new>"] },
  "implementation": { "tool": "<updated>", "alternatives": [...] },
  "multi_agent": { "tool": "<updated>", "alternatives": [...] },
  "profile": { ... unchanged ... },
  "review": {
    "layers": ["cleanup", "peer-review", "cross-model", "e2e"],
    "tools": { "cleanup": "<updated>", "peer-review": "<updated>", "cross-model": "<updated>", "e2e": "<updated>" },
    "alternatives": { ... },
    "profiles": { ... unchanged ... }
  },
  "verification": { ... platforms updated if tools changed ... },
  "source": { ... unchanged ... },
  "scope_rule": "one-feature-per-session",
  "exit_rule": "merge-ready",
  "branch_naming": "feat/{id}-{slug}"
}
```

Update `source.resolved_at` to the current ISO 8601 UTC timestamp.

### Step 6: Commit

```bash
git add .flywheel/flywheel-config.json
git commit -m "chore(flywheel): retool — re-detected available tools"
```

Verify nothing else was staged. If git status shows any other modified files, **STOP** and report — retool must be non-destructive.

### Step 7: Output Summary

```
✅ Retool complete

Changed spokes:
  - planning: built-in → planning-with-files
  - e2e: built-in → playwright

Unchanged:
  - cross-model, multi-agent, cleanup, peer-review

Run /flywheel:relay to use the new tools.
```

## When to Use

- After installing a new Claude Code plugin (e.g., `/plugin install playwright@...`)
- After uninstalling a plugin you previously configured
- When a plugin's commands are no longer detected (`config drift`)
- Before a relay session if you want to make sure the config matches reality

## When NOT to Use

- For a fresh project — use `/flywheel:init` instead
- To change feature checklist — use `/flywheel:features`
- To change platform detection (web/ios/android) — re-run `/flywheel:init` (rare; platforms change less than tools)
