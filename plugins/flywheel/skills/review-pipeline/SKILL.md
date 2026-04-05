---
name: review-pipeline
description: Use when reviewing code changes before merge — 4-layer review pipeline (cleanup, peer review, cross-model, E2E) with framework-agnostic tool slots and a zero-dependency fallback
---

# Review Pipeline

## Overview

A 4-layer review pipeline where each layer catches what the previous one misses. Layer 1 (cleanup) handles hygiene, Layer 2 (peer review) catches logic bugs, Layer 3 (cross-model) eliminates model-specific blind spots, Layer 4 (E2E) proves it actually works. Layers are framework-agnostic — slot in whatever tools are available.

## When to Use

- After implementing a feature, before merging
- As the review step in the flywheel Coding Agent loop (Step 8 of 10: Implement → Review → Verify → Commit)
- Any time code changes need quality verification

## When NOT to Use

- Planning or architecture decisions — use the planning spoke
- Exploratory research with no code to review

## 4-Layer Pipeline

| Layer | Purpose | Catches | Example Tools |
|-------|---------|---------|---------------|
| **1. Cleanup** | Code hygiene, reuse, simplification | Dead code, duplication, unnecessary complexity | superpowers /simplify, manual review prompt |
| **2. Peer review** | Logic, bugs, security, conventions | Off-by-one, injection, race conditions, pattern violations | gstack /review, superpowers peer-reviewer |
| **3. Cross-model** | Blind spots of the authoring model | Systematic biases, assumptions the first model made | codex:review (plugin), gstack /codex, Gemini CLI |
| **4. E2E verification** | Does it actually work? | Integration failures, UI broken, API contract violations | gstack /qa, Playwright, manual browser test |

## Tiers & Profiles

Which layers run depends on the **active profile** selected at relay time:

| Profile | Layers that run | Typical use |
|---------|----------------|-------------|
| **full** | All 4 (cleanup + peer review + cross-model + E2E) | High-priority or security-sensitive features |
| **standard** | Peer review (top 5) + E2E | Default for most features |
| **light** | Peer review (verdict only) | Low-priority features |
| **draft** | None — planning only | Rapid prototyping |

What you lose by skipping:
- Skip cleanup → dead code and duplication accumulate
- Skip cross-model → model-specific blind spots go undetected
- Skip E2E → integration failures slip through

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

## E2E Verification — Platform-Aware

Layer 4 is **platform-aware**. Different project types need different E2E strategies. The platform(s) are detected during `flywheel:init` and stored in `flywheel-config.json` under `review.e2e`.

### E2E Execution Flow

1. Read `review.e2e.platforms` from `.flywheel/flywheel-config.json`
2. For each configured platform, run its selected tool
3. Always run the built-in fallback (test suite + health check) regardless of platform tools
4. Aggregate results — any critical failure from any platform blocks merge

### Platform Tool Matrix

| Platform | Tool Options | What It Tests |
|----------|-------------|---------------|
| **web** | Playwright MCP/CLI, gstack /qa | Browser rendering, navigation, forms, API calls |
| **ios** | mobile-mcp, ios-simulator-mcp, Maestro | Simulator UI, tap/swipe, screen assertions |
| **android** | mobile-mcp, Maestro | Emulator UI, tap/swipe, screen assertions |
| **electron** | electron-playwright-mcp, Playwright `_electron` | Desktop app window, webview content |
| **tauri** | tauri-plugin-mcp | Desktop app via IPC, screenshots, DOM |
| **flutter-desktop** | `flutter test integration_test/`, Patrol | Widget integration, platform-specific behavior |
| **audio-plugin** | pluginval, Playwright (webview UI on Windows) | Plugin format compliance, DSP, webview UI |
| **api** | built-in (test suite + curl health endpoint) | HTTP status, response schema, error handling |
| **cli** | built-in (invoke with `--help`, check exit code) | Exit codes, stdout, basic invocation |

### Built-in E2E Fallback (Zero-Dependency)

Always runs regardless of platform tools:

1. Run `init.sh` / `init.ps1` — confirm exit code 0
2. Auto-detect and run the project test suite (`npm test`, `pytest`, `cargo test`, etc.)
3. If web app: `curl` the health/root endpoint — confirm HTTP 200
4. If CLI: run with `--help` or basic invocation — confirm exit code 0

Any step failure → report as critical issue.

### Multi-Platform Projects

A project can have multiple platforms (e.g., a monorepo with `web` + `ios` + `android`). Each platform runs its own E2E tool independently. Results are merged into a single report.

## Framework Slots

| Layer | Tool Options |
|-------|-------------|
| Cleanup | superpowers /simplify, built-in prompt |
| Peer review | gstack /review, superpowers peer-reviewer, built-in prompt |
| Cross-model | codex:review (plugin), codex:adversarial-review (plugin), gstack /codex, Gemini CLI |
| E2E — web | gstack /qa, Playwright MCP/CLI, built-in smoke test |
| E2E — ios | mobile-mcp, ios-simulator-mcp, Maestro MCP, built-in smoke test |
| E2E — android | mobile-mcp, Maestro MCP, built-in smoke test |
| E2E — electron | electron-playwright-mcp, Playwright `_electron`, built-in smoke test |
| E2E — tauri | tauri-plugin-mcp, built-in smoke test |
| E2E — flutter-desktop | `flutter test integration_test/`, Patrol, built-in smoke test |
| E2E — audio-plugin | pluginval (format + DSP), Playwright CDP (webview UI, Windows only), built-in smoke test |
| E2E — api/cli | built-in smoke test (always available) |

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
| Playwright | `mcp__plugin_playwright_playwright__*` MCP tools or `playwright` plugin in skills list |
| Gemini CLI | `gemini` command in PATH |
| mobile-mcp | `npx @mobilenext/mobile-mcp@latest --help` exits 0, or MCP tools with `mobile` prefix |
| ios-simulator-mcp | `npx ios-simulator-mcp --help` exits 0, or MCP tools with `ios_simulator` prefix |
| Maestro | `which maestro` or `maestro --version` exits 0 |
| Maestro MCP | MCP tools with `maestro` prefix after `maestro mcp` |
| electron-playwright-mcp | MCP tools with `electron` prefix |
| tauri-plugin-mcp | MCP tools with `tauri` prefix |
| pluginval | `which pluginval` or `pluginval --version` exits 0 |
| Patrol | `patrol_cli` in dev dependencies (`pubspec.yaml`) |
