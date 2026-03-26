---
name: multi-agent
description: Use when coordinating multiple agents working in parallel — defines role-based agent patterns, branch isolation, and merge strategy for flywheel
---

# Multi-Agent Coordination

## Overview

Each agent has a **role** and a **stop condition**. This is structured coordination, not "many terminals."

```
Orchestrator (human)
  +-- Planner agent(s)    — produce spec + checklist
  +-- Coding agent(s)     — one feature each, parallel on separate branches
  +-- Review agent(s)     — review completed features
  +-- QA agent            — E2E verification
```

## Key Principles

1. **Branch isolation.** Parallel agents must work on separate branches/worktrees. Never two agents on the same branch.
2. **Branch naming from config.** Follows `flywheel-config.json`'s `branch_naming` pattern (default: `feat/{id}-{slug}`).

## Merge / Integration Strategy

When parallel agents complete their features:

| Step | Action | Detail |
|------|--------|--------|
| 1 | **Orchestrator decides merge order** | Review completed branches; pick order based on dependencies and conflict likelihood |
| 2 | **Rebase onto main** | Each feature branch rebases onto latest main before merging. Keeps history linear. |
| 3 | **Conflict resolution** | If rebase conflicts arise, the Coding Agent for that feature resolves them in a new session (reads handoff log, sees conflict, resolves, re-runs smoke test) |
| 4 | **Handoff log consistency** | Each branch has its own `claude-progress.jsonl` entries. On merge, entries are appended to main's log in merge order. |
| 5 | **Checklist consistency** | `feature-checklist.json` on main is source of truth. Feature branches update their own feature's status only. On merge, checklist is updated on main. |

## Framework Slot

| Tool | Install | What it provides |
|------|---------|-----------------|
| **gstack** | `git clone` gstack repo | `/plan-ceo-review`, `/plan-eng-review`, `/review`, `/qa`, `/ship` + Conductor for parallel sprints |
| **superpowers** | Already a Claude Code plugin | `dispatching-parallel-agents`, `subagent-driven-development`, `code-reviewer` agent |
| **Claude Code native** | Built-in | `--worktree` for isolation, `Agent` tool with `subagent_type` for parallel dispatch |

## Detection

| Framework | How to detect |
|-----------|---------------|
| gstack | gstack commands in available skills |
| superpowers | `dispatching-parallel-agents` skill present |
| Native | Always available |
