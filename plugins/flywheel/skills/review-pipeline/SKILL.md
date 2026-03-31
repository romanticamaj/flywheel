---
name: review-pipeline
description: Use when reviewing code changes before merge — 4-layer review pipeline (self-review, code review, cross-model, E2E) with framework-agnostic tool slots and a zero-dependency fallback
---

# Review Pipeline

## Overview

A 4-layer code review pipeline where each layer catches what the previous one misses. Layer 1 handles hygiene, Layer 2 catches logic bugs, Layer 3 eliminates model-specific blind spots, Layer 4 proves it actually works. Layers are framework-agnostic — slot in whatever tools are available.

## When to Use

- After implementing a feature, before merging
- As the review step in the flywheel Coding Agent loop (step 7 of 8: Implement → Review → Commit)
- Any time code changes need quality verification

## When NOT to Use

- Planning or architecture decisions — use the planning spoke
- Exploratory research with no code to review

## 4-Layer Pipeline

| Layer | Purpose | Catches | Example Tools |
|-------|---------|---------|---------------|
| **1. Self-review** | Code hygiene, reuse, simplification | Dead code, duplication, unnecessary complexity | superpowers /simplify, manual review prompt |
| **2. Code review** | Logic, bugs, security, conventions | Off-by-one, injection, race conditions, pattern violations | gstack /review, superpowers code-reviewer |
| **3. Cross-model** | Blind spots of the authoring model | Systematic biases, assumptions the first model made | codex:review (plugin), gstack /codex, Gemini CLI |
| **4. E2E verification** | Does it actually work? | Integration failures, UI broken, API contract violations | gstack /qa, Playwright, manual browser test |

## Tiers

| Tier | Layers | When |
|------|--------|------|
| **Minimum** | Layer 2 (code review) + Layer 4 (E2E) | Required for every session |
| **Recommended** | All 4 layers | When tools are available |

What you lose by skipping:
- Skip Layer 1 → dead code and duplication accumulate
- Skip Layer 3 → model-specific blind spots go undetected

## Contract Per Layer

| Field | Value |
|-------|-------|
| **Input** | Code diff or branch |
| **Output** | List of issues with severity: `critical` / `warning` / `info` |
| **Gate** | Critical issues block merge |

## Cross-Model Insight

| Scenario | Confidence | Action |
|----------|------------|--------|
| Both models flag the same issue | High | Fix it |
| Only one model flags it | Low | Needs human judgment |

## Built-in E2E Fallback (Zero-Dependency)

When no E2E tool is installed, run this sequence:

1. Run `init.sh` / `init.ps1` — confirm exit code 0
2. Auto-detect and run the project test suite (`npm test`, `pytest`, `cargo test`, etc.)
3. If web app: `curl` the health/root endpoint — confirm HTTP 200
4. If CLI: run with `--help` or basic invocation — confirm exit code 0

Any step failure → report as critical issue.

## Framework Slots

| Layer | Tool Options |
|-------|-------------|
| Self-review | superpowers /simplify, built-in prompt |
| Code review | gstack /review, superpowers code-reviewer, built-in prompt |
| Cross-model | codex:review (plugin), codex:adversarial-review (plugin), gstack /codex, Gemini CLI |
| E2E | gstack /qa, Playwright, built-in smoke test |

## Detection

How to detect each tool at runtime:

| Tool | Detection Method |
|------|-----------------|
| superpowers /simplify | `code-simplifier` in skills list |
| gstack /review | `gstack review` in skills list |
| codex:review (plugin) | `codex:review` in skills/commands list |
| codex:adversarial-review (plugin) | `codex:adversarial-review` in skills/commands list |
| gstack /codex | `gstack codex` in skills list |
| codex CLI (direct) | `codex` command in PATH |
| Playwright | `playwright` in `node_modules` or available via `npx` |
| Gemini CLI | `gemini` command in PATH |
