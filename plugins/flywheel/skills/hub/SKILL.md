---
name: hub
description: Use when starting a long-running project that will span multiple sessions — sets up zero-cost session handoffs with an Initializer + Coding Agent relay protocol, auto-detects planning, multi-agent, and review tools
---

# Flywheel

## Overview

Long-running agent work succeeds through zero-cost session handoffs, not through one long session that burns out its context window. Flywheel uses a dual-prompt architecture: an **Initializer** (run once) sets up the project with tool detection and artifact generation, then a **Coding Agent** (run N times) executes an 9-step loop — each session implements one feature and leaves a machine-readable handoff for the next. Works out-of-the-box with zero dependencies (just Claude Code + filesystem), upgradable with framework tools at any time.

## When to Use

- Starting a project that will take multiple sessions
- Resuming work on a project with flywheel already set up
- Any task too large for a single context window

## When NOT to Use

- Quick one-off tasks that fit in one session
- Pure research or exploration (no code to commit)

## Two Phases

### Phase 1: Initializer (run once)

Run once per project or epic. Detects installed tools, prompts the user to choose per spoke, and creates all artifacts in `.flywheel/`.

See `initializer-template.md` for the full Initializer protocol — runtime detection algorithm, tool selection prompts, artifact generation, and initial commit sequence.

### Phase 2: Coding Agent (run N times)

Each session follows an 9-step loop: validate config, read handoff log, read checklist, bootstrap, smoke test, plan the implementation, implement one feature, review + verify, commit + handoff.

See `coding-agent-template.md` for the full Coding Agent protocol — step-by-step instructions, error handling table, exit rule, and scope rule.

## Spokes Reference

| Spoke | Skill | What it provides |
|---|---|---|
| Planning | `flywheel:planning` | Framework slot for planning tools, `feature-checklist.json` schema |
| Multi-Agent | `flywheel:multi-agent` | Role-based coordination + merge strategy |
| Review | `flywheel:review-pipeline` | 4-layer review pipeline with framework slots |

Each spoke is independent and defines its own contract, detection logic, and framework slots. The hub references them; they do not depend on each other.

## Quick Start

1. Run `/flywheel:init` to set up the project.
2. The Initializer detects installed tools, asks you to choose per spoke, and creates `.flywheel/` artifacts (config, checklist, init scripts, empty handoff log).
3. Describe your features. The agent generates a prioritized `feature-checklist.json`.
4. Run `/flywheel:relay` to start a coding session — picks the next feature, implements it, reviews it, commits merge-ready code, and writes a handoff entry.
5. Repeat `/flywheel:relay` until the checklist is complete.

## flywheel-config.json Reference

Path: `.flywheel/flywheel-config.json`

```json
{
  "planning": {
    "tool": "built-in",
    "alternatives": ["planning-with-files", "openspec", "superpowers"]
  },
  "multi_agent": {
    "tool": "claude-code-native",
    "alternatives": ["gstack", "superpowers"]
  },
  "review": {
    "layers": ["self-review", "code-review", "cross-model", "e2e"],
    "tools": {
      "self-review": "built-in",
      "code-review": "built-in",
      "cross-model": null,
      "e2e": "built-in"
    },
    "alternatives": {
      "self-review": ["superpowers:/simplify"],
      "code-review": ["gstack:/review", "superpowers:code-reviewer"],
      "cross-model": ["gstack:/codex", "gemini-cli"],
      "e2e": ["gstack:/qa", "playwright"]
    }
  },
  "source": {
    "type": "file",
    "paths": ["SPEC.md"],
    "user_notes": "Also add rate limiting on all endpoints",
    "resolved_at": "2026-03-27T00:00:00Z"
  },
  "scope_rule": "one-feature-per-session",
  "exit_rule": "merge-ready",
  "branch_naming": "feat/{id}-{slug}"
}
```

### Field Reference

| Field | Type | Description |
|---|---|---|
| `planning.tool` | string | Active planning tool or `"built-in"` |
| `planning.alternatives` | string[] | Known planning tools for future upgrades |
| `multi_agent.tool` | string | Active multi-agent tool or `"claude-code-native"` |
| `multi_agent.alternatives` | string[] | Known multi-agent tools for future upgrades |
| `review.layers` | string[] | Fixed 4-layer pipeline: `["self-review", "code-review", "cross-model", "e2e"]` |
| `review.tools` | object | Per-layer tool choice; `null` means layer is skipped |
| `review.alternatives` | object | Per-layer list of known tools for future upgrades |
| `source.type` | string | How the checklist was sourced: `"file"`, `"user-input"`, `"codebase"`, or `"mixed"` |
| `source.paths` | string[] | Spec files used as input |
| `source.user_notes` | string\|null | Extra context from user conversation |
| `source.resolved_at` | string | ISO 8601 timestamp |
| `scope_rule` | enum | `"one-feature-per-session"` — enforces single-feature sessions |
| `exit_rule` | enum | `"merge-ready"` — no WIP commits allowed |
| `branch_naming` | template | Branch name pattern with `{id}` and `{slug}` placeholders |

## Non-Goals

- **Not a CI/CD tool** — doesn't deploy anything
- **Not a project manager** — doesn't assign work to humans
- **Not a framework** — doesn't provide UI components or libraries
- **Doesn't replace any existing tool** — orchestrates them

## Common Mistakes

- **Trying to one-shot the whole app.** Context burns out mid-implementation. Use flywheel to break work into one-feature sessions with clean handoffs.
- **Agent declares done prematurely.** Needs E2E verification, not just unit tests. The review pipeline (minimum tier: code review + E2E) catches this.
- **Agent does multiple features per session.** Leads to scope creep and half-finished work. The scope rule enforces one feature per session.
- **Skipping the handoff log.** The next session has no context and starts from scratch. Every session must append to `claude-progress.jsonl` before exiting.
- **Silently skipping review tools.** Agent substitutes a "similar" tool or skips a layer without attempting the configured tool first. The coding agent template now requires: attempt configured tool → log error if it fails → ask user before fallback → output compliance table at session end. See `coding-agent-template.md` Stage Tracker and Step 8a enforcement rules.
