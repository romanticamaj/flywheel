# Flywheel — Initializer Template

This is a reference template for the Initializer phase of the flywheel protocol. The hub skill (`flywheel/SKILL.md`) cross-references this document when running Phase 1 setup on a new project.

---

## 0. Pre-Flight: Recommended Starter Pack

**Run this BEFORE the detection algorithm.** New users often have no plugins installed, leading to a wall of ⬜ options and a hollow flywheel. This step detects what's missing and guides the user through installing each tool one at a time.

### Step 0a: Detect what's installed

Run these checks silently (do not show commands to user):

```bash
# Check superpowers — look for skill names in Claude Code skills list
# Present: if any of these skills exist: "superpowers:brainstorming", "superpowers:writing-plans",
#          "superpowers:dispatching-parallel-agents", "simplify"

# Check planning-with-files — look for skill name in Claude Code skills list
# Present: if "planning-with-files" skill exists

# Check codex — look for skill/command names in Claude Code skills/commands list
# Present: if "codex:setup" or "codex:rescue" skill exists

# Check playwright — look for MCP tools or skill names in Claude Code
# Present: if any mcp__plugin_playwright_playwright__* tools exist,
#          or "playwright" appears in the skills/plugins list
```

### Step 0b: Show the status board

Present a single status board showing what's installed and what's missing:

```
RECOMMENDED TOOLS — status
┌───┬──────────────────┬──────────────────────────────────┬───────────┐
│ # │ Tool             │ Covers                           │ Status    │
├───┼──────────────────┼──────────────────────────────────┼───────────┤
│ 1 │ superpowers      │ Cleanup, peer review,            │ ✅ / ⬜   │
│   │                  │ multi-agent                      │           │
│ 2 │ planning-w-files │ File-based planning              │ ✅ / ⬜   │
│   │                  │ (task_plan.md, progress)          │           │
│ 3 │ codex            │ Cross-model review               │ ✅ / ⬜   │
│   │                  │ (requires OpenAI/ChatGPT)        │           │
│ 4 │ Playwright       │ Web E2E verification             │ ✅ / ⬜   │
└───┴──────────────────┴──────────────────────────────────┴───────────┘

Note: Playwright covers web E2E. For mobile, desktop, and audio plugin E2E,
additional platform-specific tools are configured in Section 2 (Review — E2E).
```

- **✅** = detected, no action needed
- **⬜** = not installed

**If all 4 are ✅:** Say "All recommended tools installed!" and proceed to Section 1 (detection).

**If any are ⬜:** Show install options:

```
  Install options:
    1) Install all missing tools (recommended)
    2) Pick which to install
    3) Skip — use built-in defaults
```

### Step 0c: Guided installation

**If user picks 1 (install all)** or **picks 2 (selective)**, walk through each missing tool one at a time in this order. For each tool:

1. Show what it does and why
2. Run the install command
3. Verify it worked
4. Show ✅ and move to the next

#### Tool 1: superpowers

```
Installing superpowers — covers cleanup, peer review, and multi-agent dispatch...
Source: https://github.com/obra/superpowers
```

**Install:**
```
/plugin install superpowers@claude-plugins-official
```

**Verify:** Check that `superpowers:brainstorming` or `simplify` now appears in the skills list after `/reload-plugins`.

**If install fails:** Show the error and offer alternatives:
```
superpowers install failed: [error]
  A) Retry
  B) Skip — cleanup and peer-review will use built-in defaults
```

#### Tool 2: planning-with-files

```
Installing planning-with-files — file-based planning with task_plan.md and progress tracking...
Source: https://github.com/OthmanAdi/planning-with-files
```

**Install:**
```bash
npx skills add OthmanAdi/planning-with-files --skill planning-with-files -g
```

**Verify:** Check that `planning-with-files` now appears in the skills list after `/reload-plugins`.

**If install fails:** Show the error and offer alternatives:
```
planning-with-files install failed: [error]
  A) Retry
  B) Try alternative: /plugin marketplace add OthmanAdi/planning-with-files && /plugin install planning-with-files@planning-with-files
  C) Skip — planning will use built-in default
```

#### Tool 3: codex

```
Installing codex — cross-model review using OpenAI's Codex (catches Claude's blind spots)...
Source: https://github.com/openai/codex-plugin-cc
Requires: OpenAI API key or ChatGPT account
```

**Install (2 steps + verify):**
```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
```

**Verify:** Run `/codex:setup` to confirm the Codex CLI is installed and authenticated. If the CLI is missing, `/codex:setup` will offer to install it via `npm install -g @openai/codex`.

**Verify:** Check that `codex:setup` or `codex:rescue` now appears in the skills list.

**If user doesn't have an OpenAI account:** Say:
```
Codex requires an OpenAI/ChatGPT account. You can:
  A) Sign up at https://platform.openai.com and continue
  B) Skip — cross-model review will be disabled (you can add it later)
```

#### Tool 4: Playwright

```
Installing Playwright — real browser automation for E2E verification...
Source: https://github.com/anthropics/claude-plugins-public/tree/main/external_plugins/playwright
```

**Install:**
```
/plugin install playwright@claude-plugins-official
```

**Verify:** Check that `mcp__plugin_playwright_playwright__browser_navigate` or similar Playwright MCP tools appear after `/reload-plugins`.

**If install fails:** Show the error and offer alternatives:
```
Playwright install failed: [error]
  A) Retry
  B) Skip — E2E will use built-in smoke test (test suite + health check)
```

### Step 0d: Final status

After all installations, show the updated status board:

```
RECOMMENDED TOOLS — final status
┌───┬──────────────────┬───────────┐
│ # │ Tool             │ Status    │
├───┼──────────────────┼───────────┤
│ 1 │ superpowers      │ ✅        │
│ 2 │ planning-w-files │ ✅        │
│ 3 │ codex            │ ✅        │
│ 4 │ Playwright       │ ⬜ skipped│
└───┴──────────────────┴───────────┘

3/4 tools installed. Proceeding to detection...
```

Run `/reload-plugins` once to make all newly installed skills available, then proceed to Section 1 (detection).

### Step 0e: Skip path

**If user picks 3 (skip):** Say "Using built-in defaults. You can install tools later and re-run `/flywheel:init`." Proceed directly to Section 1.

**Do NOT block on this step.** If the user wants to skip, let them. The per-spoke selection (Section 2) still shows all tools with install commands.

---

## 1. Runtime Detection Algorithm

Execute these 7 steps in order at Initializer startup. (If the pre-flight installed plugins, their skills will now appear in detection.)

### Step 1: Scan Claude Code Skills List

Check the active Claude Code skills list for known skill names:

| Spoke | Skill names to look for |
|---|---|
| Planning | `planning-with-files`, `superpowers` (brainstorming / writing-plans) |
| Multi-agent | `gstack` (Conductor commands), `superpowers` (dispatching-parallel-agents, subagent-driven-development) |
| Review — cleanup | `superpowers` (code-simplifier / /simplify) |
| Review — peer-review | `gstack` (/review), `superpowers` (peer-reviewer) |
| Review — cross-model | `codex:review` or `codex:rescue` (codex-plugin-cc — **primary**), `gstack` (/codex) |
| Review — E2E (web) | `gstack` (/qa), `playwright` (MCP tools: `mcp__plugin_playwright_playwright__*`) |
| Review — E2E (mobile) | `mobile-mcp` (MCP tools with `mobile` prefix), `ios-simulator-mcp` (MCP tools with `ios_simulator` prefix), `maestro` CLI in PATH |
| Review — E2E (desktop) | `electron-playwright-mcp` (MCP tools with `electron` prefix), `tauri-plugin-mcp` (MCP tools with `tauri` prefix) |
| Review — E2E (audio-plugin) | `pluginval` CLI in PATH |

### Step 2: Check node_modules for npm Packages

Search both local and global installations:

```
# Local
ls node_modules/openspec 2>/dev/null

# Global
npm list -g openspec --depth=0 2>/dev/null
```

| Package | Maps to spoke |
|---|---|
| `openspec` | Planning |

### Step 3: Check PATH for CLI Tools

```
which gemini 2>/dev/null || where gemini 2>NUL
which codex 2>/dev/null || where codex 2>NUL
which maestro 2>/dev/null || where maestro 2>NUL
which pluginval 2>/dev/null || where pluginval 2>NUL
```

| CLI tool | Maps to spoke | Note |
|---|---|---|
| `gemini` | Review — cross-model | Gemini CLI |
| `codex` | Review — cross-model | **Only use as fallback.** If `codex:review` or `codex:rescue` skills were detected in Step 1, the codex-plugin-cc is installed — prefer `codex:review` over bare CLI. Only map to `codex-cli` if the plugin skills are NOT detected. |
| `maestro` | Review — E2E (mobile) | Maestro E2E framework — supports iOS + Android |
| `pluginval` | Review — E2E (audio-plugin) | Tracktion pluginval — plugin format compliance testing |

> **Note:** Playwright is now a Claude Code plugin (not an npm package). It is detected in Step 1 via MCP tool names (`mcp__plugin_playwright_playwright__*`).

### Step 4: Build Available-Tools Map

Merge results from Steps 1-3 into a single map:

```json
{
  "planning": ["planning-with-files", "openspec", "superpowers"],
  "multi_agent": ["gstack", "superpowers", "claude-code-native"],
  "review": {
    "cleanup": ["superpowers:/simplify"],
    "peer-review": ["gstack:/review", "superpowers:peer-reviewer"],
    "cross-model": ["codex:review", "gstack:/codex", "gemini-cli"],
    "e2e": {
      "detected_platforms": ["web", "ios", "android"],
      "tools": {
        "web": ["gstack:/qa", "playwright"],
        "ios": ["mobile-mcp", "ios-simulator-mcp", "maestro"],
        "android": ["mobile-mcp", "maestro"]
      }
    }
  }
}
```

Only include tools that were actually detected. `claude-code-native` is always present for multi-agent.

**Cross-model priority rule:** If `codex:review` or `codex:rescue` skills are detected (Step 1), list `codex:review` in the map — this is the codex-plugin-cc and is the **primary recommended** cross-model tool. Only list `codex-cli` if the plugin skills are NOT detected but the `codex` binary is in PATH (Step 3). Never list both — the plugin supersedes the bare CLI.

### Step 5: Present Findings and Prompt User

Apply the selection rule for each spoke:

| Condition | Action |
|---|---|
| Multiple tools detected | Prompt user to choose from detected options + built-in default |
| One tool detected | Suggest it, confirm with user |
| No tools detected | Use built-in default, show installation hint |

See Section 2 below for exact prompt templates.

### Step 6: Save Choices

Write the user's selections to `.flywheel/flywheel-config.json`. See Section 3 for the full schema.

### Step 7: Commit Config with Initial Project Setup

Create the initial commit containing all generated artifacts. See Section 5 for the commit sequence.

---

## 2. Tool Selection Prompts

**Always show all known tools**, not just detected ones. Mark each tool's availability so the user can see what they're missing and install it if they want. This lets users make informed choices instead of only seeing what's already installed.

### Presentation format

For each spoke, present a **full tool menu** using this format:

```
[Spoke Name] — [what this spoke does]

  1. ✅ tool-name — [description]                    (installed)
  2. ⬜ tool-name — [description]                    (not installed)
     Install: [install command]
  3. ✅ built-in — [description]                      (always available)
```

- **✅** = detected in Steps 1-3
- **⬜** = known but not installed, with install command shown
- The user can pick any option. If they pick an uninstalled tool, **pause and help them install it** before continuing.

### Full Tool Catalog

Present one table per spoke. Always include every tool in the catalog, regardless of detection.

#### Planning

> **Planning** — generates the prioritized feature checklist from your spec.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **planning-with-files** | File-based planning with task_plan.md, findings.md, progress.md | `npx skills add OthmanAdi/planning-with-files --skill planning-with-files -g` |
> | 2 | ✅/⬜ | **superpowers** | Brainstorming + writing-plans skills | Already a Claude Code plugin — install via `/plugin install superpowers@claude-plugins-official` |
> | 3 | ✅/⬜ | **OpenSpec** | Structured proposal.md + specs/ directory | `npm install -g openspec` |
> | 4 | ✅ | **built-in** | Claude generates feature-checklist.json directly, no dependencies | Always available |

#### Multi-Agent

> **Multi-agent** — coordinates parallel agents working on separate features.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gstack** | Conductor for parallel sprints + /plan-ceo-review, /plan-eng-review, /review, /qa, /ship | Add gstack as plugin — see https://github.com/garrytan/gstack |
> | 2 | ✅/⬜ | **superpowers** | dispatching-parallel-agents, subagent-driven-development | Already a Claude Code plugin — install via `/plugin install superpowers@claude-plugins-official` |
> | 3 | ✅ | **claude-code-native** | Built-in `--worktree` isolation + `Agent` tool, no dependencies | Always available |

#### Review — Cleanup

> **Cleanup** — catches dead code, duplication, unnecessary complexity.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **superpowers /simplify** | Code simplifier agent | Already a Claude Code plugin — install via `/plugin install superpowers@claude-plugins-official` |
> | 2 | ✅/⬜ | **gstack /simplify** | gstack code simplifier | Add gstack as plugin — see https://github.com/garrytan/gstack |
> | 3 | ✅ | **built-in** | Manual diff review prompt | Always available |

#### Review — Peer review

> **Peer review** — catches logic bugs, security issues, convention violations.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gstack /review** | Pre-landing PR review with SQL safety, trust boundary analysis | Add gstack as plugin — see https://github.com/garrytan/gstack |
> | 2 | ✅/⬜ | **superpowers peer-reviewer** | Peer reviewer subagent | Already a Claude Code plugin — install via `/plugin install superpowers@claude-plugins-official` |
> | 3 | ✅ | **built-in** | Spawn a peer-reviewer subagent with built-in prompt | Always available |

#### Review — Cross-model

> **Cross-model** — catches systematic biases and blind spots of the authoring model.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **codex:review** | Official OpenAI Codex plugin — standard + adversarial review modes, background jobs, stop gate | `/plugin marketplace add openai/codex-plugin-cc && /plugin install codex@openai-codex` |
> | 2 | ✅/⬜ | **gstack /codex** | gstack Codex wrapper — simpler interface, adversarial challenge mode | Add gstack as plugin — see https://github.com/garrytan/gstack |
> | 3 | ✅/⬜ | **gemini-cli** | Gemini CLI for second-opinion review | `npm install -g @google/gemini-cli` or check if `gemini` is in PATH |
> | 4 | ✅/⬜ | **codex-cli** | Codex CLI directly (no plugin integration) | `npm install -g @openai/codex` |
> | 5 | — | **Skip** | Disable this layer | — |

#### Review — E2E

E2E is **platform-aware**. Instead of picking one tool, first detect the project's target platform(s), then select a tool per platform.

##### Step 1: Platform Discovery

Auto-detect platforms by scanning for marker files. Check all — a project can target multiple platforms.

| Marker Files | Platform |
|---|---|
| `next.config.*`, `vite.config.*`, `webpack.config.*`, `index.html` + `package.json` | `web` |
| `*.xcodeproj`, `*.xcworkspace`, `ios/`, `Podfile` | `ios` |
| `android/`, `build.gradle`, `settings.gradle` | `android` |
| `electron-builder.*`, `electron.vite.*`, `electron/`, `main.js` + `"electron"` in package.json | `electron` |
| `tauri.conf.json`, `src-tauri/` | `tauri` |
| `pubspec.yaml` + (`windows/` or `macos/` or `linux/`) | `flutter-desktop` |
| `*.jucer`, `CMakeLists.txt` + JUCE in cmake, `JuceLibraryCode/` | `audio-plugin` |
| No UI markers, only server/API code | `api` |
| CLI entry point (`bin/`, `cli.*`, `"bin"` in package.json) | `cli` |

Present findings to the user:

```
DETECTED PLATFORMS
┌───┬─────────────────┬──────────────────────────────────┐
│ # │ Platform        │ Evidence                         │
├───┼─────────────────┼──────────────────────────────────┤
│ 1 │ web             │ next.config.ts found             │
│ 2 │ ios             │ ios/ directory found             │
│ 3 │ android         │ android/ directory found         │
└───┴─────────────────┴──────────────────────────────────┘

  Does this look right? (y/n, or add/remove platforms)
```

If no platforms detected, ask: "What platforms does this project target? (web, ios, android, electron, tauri, flutter-desktop, audio-plugin, api, cli)"

##### Step 2: Tool Selection Per Platform

For each detected platform, show available tools:

> **E2E — web** — browser-based verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gstack /qa** | Systematic QA with headless browser, finds + fixes bugs | Add gstack as plugin — see https://github.com/garrytan/gstack |
> | 2 | ✅/⬜ | **Playwright** | Browser automation (Claude Code plugin with MCP tools) | `/plugin install playwright@claude-plugins-official` |
> | 3 | ✅ | **built-in** | Run test suite + curl health endpoint | Always available |

> **E2E — ios** — iOS simulator/device verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **mobile-mcp** | Unified iOS+Android MCP — simulators + real devices, a11y-based | `npx -y @mobilenext/mobile-mcp@latest` (add as MCP server) |
> | 2 | ✅/⬜ | **ios-simulator-mcp** | iOS simulator MCP — screenshots, tap, type, swipe | `npx -y ios-simulator-mcp` (add as MCP server) |
> | 3 | ✅/⬜ | **Maestro** | YAML-based E2E flows, cross-platform, official MCP | `curl -fsSL "https://get.maestro.mobile.dev" \| bash` |
> | 4 | ✅ | **built-in** | Run test suite (`xcodebuild test`) | Always available |

> **E2E — android** — Android emulator/device verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **mobile-mcp** | Unified iOS+Android MCP — emulators + real devices, a11y-based | `npx -y @mobilenext/mobile-mcp@latest` (add as MCP server) |
> | 2 | ✅/⬜ | **Maestro** | YAML-based E2E flows, cross-platform, official MCP | `curl -fsSL "https://get.maestro.mobile.dev" \| bash` |
> | 3 | ✅ | **built-in** | Run test suite (`./gradlew connectedAndroidTest`) | Always available |

> **E2E — electron** — Electron desktop app verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **electron-playwright-mcp** | A11y-first Electron automation via Playwright | Add MCP server — see https://github.com/fracalo/electron-playwright-mcp |
> | 2 | ✅/⬜ | **Playwright** | `_electron.launch()` for full Electron control | `/plugin install playwright@claude-plugins-official` |
> | 3 | ✅ | **built-in** | Run test suite + launch app + verify window | Always available |

> **E2E — tauri** — Tauri desktop app verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **tauri-plugin-mcp** | Screenshots, DOM inspection, input simulation for Tauri v2 | Add MCP server — see https://github.com/P3GLEG/tauri-plugin-mcp |
> | 2 | ✅/⬜ | **Playwright (Windows only)** | Attach to WebView2 via CDP (`connectOverCDP`) | `/plugin install playwright@claude-plugins-official` |
> | 3 | ✅ | **built-in** | Run test suite (`cargo test`) + launch app | Always available |

> **E2E — flutter-desktop** — Flutter desktop app verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **Patrol** | Extended integration_test with native view testing, sharding | Add `patrol` to `dev_dependencies` in pubspec.yaml |
> | 2 | ✅ | **built-in** | `flutter test integration_test/` | Always available |

> **E2E — audio-plugin** — JUCE/audio plugin verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **pluginval** | Plugin format compliance, crash detection, param fuzz testing (strictness 1-10) | Download from https://github.com/Tracktion/pluginval/releases or build via CMake |
> | 2 | ✅/⬜ | **Playwright (webview UI, Windows only)** | Attach to JUCE WebView2 via CDP for UI testing | `/plugin install playwright@claude-plugins-official` |
> | 3 | ✅ | **built-in** | Run test suite (Catch2/GoogleTest via `ctest` or `cmake --build . --target test`) | Always available |
>
> **Note:** For JUCE webview UIs, the JS frontend can also be tested independently with Playwright against a dev server (all platforms). Only attaching to the webview inside the running plugin requires Windows + WebView2 CDP.

> **E2E — api** — API/backend verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅ | **built-in** | Run test suite + `curl` health/root endpoint + verify HTTP 200 | Always available |

> **E2E — cli** — CLI tool verification.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅ | **built-in** | Invoke with `--help` or basic args + verify exit code 0 | Always available |

### Install-on-demand flow

If the user picks a tool marked ⬜ (not installed):

1. **Web fetch the tool's repo/docs for the latest install instructions.** Do not rely on hardcoded commands — install steps change over time. Fetch the README or install guide from the tool's source URL listed in the catalog table above.
2. Show the install steps from the fetched guide.
3. Ask: "Want me to install it now, or proceed with a different option?"
4. If yes — run the install steps, verify it worked, then continue.
5. If no — ask them to pick another option.

**Tool source URLs for install guides:**

| Tool | Source URL |
|------|-----------|
| superpowers | https://github.com/obra/superpowers |
| planning-with-files | https://github.com/OthmanAdi/planning-with-files |
| codex (codex-plugin-cc) | https://github.com/openai/codex-plugin-cc |
| playwright | https://github.com/anthropics/claude-plugins-public/tree/main/external_plugins/playwright |
| gstack | https://github.com/garrytan/gstack |
| OpenSpec | https://github.com/openspec/openspec |
| Gemini CLI | https://github.com/google/gemini-cli |
| mobile-mcp | https://github.com/mobile-next/mobile-mcp |
| ios-simulator-mcp | https://github.com/joshuayoes/ios-simulator-mcp |
| Maestro | https://github.com/mobile-dev-inc/maestro |
| electron-playwright-mcp | https://github.com/fracalo/electron-playwright-mcp |
| tauri-plugin-mcp | https://github.com/P3GLEG/tauri-plugin-mcp |
| pluginval | https://github.com/Tracktion/pluginval |
| Patrol | https://github.com/leancodepl/patrol |

Do NOT silently skip uninstalled tools or auto-fallback to built-in.

---

## 3. Artifact Generation

All artifacts are created in `.flywheel/` at the project root.

### `.flywheel/flywheel-config.json`

Full schema — fill in `tool` fields with user's choices from Section 2:

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
  "profile": {
    "default": "adaptive",
    "adaptive_rules": {
      "1-2": "full",
      "3-5": "standard",
      "6+": "light"
    },
    "bump_rules": {
      "first_feature": "full",
      "security_sensitive": "full",
      "has_dependencies": "+1 tier",
      "was_blocked": "full",
      "has_cross_model_tool": "+1 tier"
    }
  },
  "review": {
    "layers": ["cleanup", "peer-review", "cross-model", "e2e"],
    "tools": {
      "cleanup": "built-in",
      "peer-review": "built-in",
      "cross-model": null
    },
    "e2e": {
      "platforms": {
        "web": { "tool": "playwright", "alternatives": ["gstack:/qa", "built-in"] },
        "ios": { "tool": "mobile-mcp", "alternatives": ["ios-simulator-mcp", "maestro", "built-in"] }
      }
    },
    "alternatives": {
      "cleanup": ["superpowers:/simplify"],
      "peer-review": ["gstack:/review", "superpowers:peer-reviewer"],
      "cross-model": ["codex:review", "gstack:/codex", "gemini-cli"]
    },
    "profiles": {
      "full":     { "cleanup": true,  "peer-review": "full",    "cross-model": true,  "e2e": true  },
      "standard": { "cleanup": false, "peer-review": "top5",    "cross-model": false, "e2e": true  },
      "light":    { "cleanup": false, "peer-review": "verdict", "cross-model": false, "e2e": false },
      "draft":    { "cleanup": false, "peer-review": false,     "cross-model": false, "e2e": false }
    }
  },
  "source": {
    "type": "user-input",
    "paths": [],
    "user_notes": null,
    "resolved_at": "2026-03-27T00:00:00Z"
  },
  "scope_rule": "one-feature-per-session",
  "exit_rule": "merge-ready",
  "branch_naming": "feat/{id}-{slug}"
}
```

**Field reference:**

| Field | Type | Valid values |
|---|---|---|
| `planning.tool` | string | User's chosen tool or `"built-in"` |
| `planning.alternatives` | string[] | All known planning tools |
| `multi_agent.tool` | string | User's chosen tool or `"claude-code-native"` |
| `multi_agent.alternatives` | string[] | All known multi-agent tools |
| `profile.default` | string | `"adaptive"`, `"full"`, `"standard"`, `"light"`, or `"draft"` |
| `profile.adaptive_rules` | object | Maps feature priority ranges to profiles |
| `profile.bump_rules` | object | Conditions that override the adaptive selection |
| `review.layers` | string[] | Fixed: `["cleanup", "peer-review", "cross-model", "e2e"]` |
| `review.tools` | object | Per-layer tool choice (cleanup, peer-review, cross-model); `null` means layer is skipped |
| `review.e2e` | object | Platform-aware E2E configuration (see below) |
| `review.e2e.platforms` | object | Map of platform → `{ tool, alternatives }`. Valid platforms: `web`, `ios`, `android`, `electron`, `tauri`, `flutter-desktop`, `audio-plugin`, `api`, `cli` |
| `review.e2e.platforms.<platform>.tool` | string | Selected E2E tool for this platform, or `"built-in"` |
| `review.e2e.platforms.<platform>.alternatives` | string[] | Other known tools for this platform |
| `review.alternatives` | object | Per-layer list of known tools (cleanup, peer-review, cross-model) |
| `review.profiles` | object | Per-profile layer config: `true`/`false`/`"full"`/`"top5"`/`"verdict"` |
| `scope_rule` | string | `"one-feature-per-session"` |
| `exit_rule` | string | `"merge-ready"` |
| `branch_naming` | string | Template with `{id}` and `{slug}` placeholders |
| `source.type` | string | `"file"`, `"user-input"`, `"codebase"`, or `"mixed"` |
| `source.paths` | string[] | Spec files used as input (empty if none) |
| `source.user_notes` | string\|null | Extra context from user conversation |
| `source.resolved_at` | string | ISO 8601 timestamp of when source was resolved |

### `.flywheel/feature-checklist.json`

#### Source Resolution (run before generating the checklist)

The checklist needs a source — a spec, requirements, or user description. Resolve the source using this priority order:

**Step 1: Collect all available context.**

Gather from three layers, in order:

| Layer | What to check | Examples |
|-------|--------------|---------|
| **A. User input** | Anything the user said in the current conversation before or alongside `/flywheel:init` | "Build a todo app with auth", pasted requirements, linked docs |
| **B. Repo files** | Scan the project root and common locations for spec-like files | See detection table below |
| **C. Existing work** | Check git log, existing code structure, README for implied features | `git log --oneline -20`, directory structure |

**File detection — scan for these patterns (first match per category):**

| Pattern | What it likely contains |
|---------|----------------------|
| `SPEC.md`, `spec.md`, `SPEC` | Product specification |
| `PRD.md`, `prd.md` | Product requirements document |
| `REQUIREMENTS.md`, `requirements.md`, `REQUIREMENTS.txt` | Feature requirements |
| `DESIGN.md`, `design.md` | Design document |
| `TODO.md`, `todo.md`, `TODOS.md` | Task list |
| `openspec/`, `specs/` | OpenSpec or structured specs directory |
| `.github/ISSUE_TEMPLATE/` or GitHub issues | Issue-driven development |
| `CLAUDE.md` | May contain project goals or context |
| `README.md` | May describe intended features |

**Step 2: Merge and present.**

| What was found | Action |
|----------------|--------|
| User described features + spec files found | Merge both. Show: "I found `SPEC.md` and your description. I'll combine them into the checklist. Here's what I extracted — anything to add or change?" |
| User described features, no spec files | Use user input directly. Confirm: "Here's the checklist from your description — anything to add?" |
| No user input, spec files found | Parse the spec files. Show: "I found `PRD.md` — here are the features I extracted. Any changes or additions?" |
| No user input, no spec files, but existing code | Analyze the codebase. Show: "No spec found, but I see existing code. Here's what I think the project needs next — correct me." |
| Nothing found at all | Ask: "No spec or description found. Describe the features you want to build — bullet points, a paragraph, or paste a spec." |

**Step 3: Record the source in config.**

Add a `source` field to `flywheel-config.json`:

```json
{
  "source": {
    "type": "file",
    "paths": ["SPEC.md"],
    "user_notes": "Also add rate limiting on all endpoints",
    "resolved_at": "2026-03-27T00:00:00Z"
  }
}
```

Valid `type` values: `"file"`, `"user-input"`, `"codebase"`, `"mixed"`.

- `"file"` — checklist derived from spec files
- `"user-input"` — checklist from user's conversation input
- `"codebase"` — checklist inferred from existing code
- `"mixed"` — combination of sources

`paths` lists which files were used. `user_notes` captures any extra context the user provided on top of the detected sources. Both can be empty arrays/null.

#### Generating the checklist

After source resolution, create the version-1 wrapper and populate features:

```json
{
  "version": 1,
  "features": []
}
```

Each feature entry follows this schema:

```json
{
  "id": "feat-001",
  "title": "User authentication",
  "priority": 1,
  "status": "pending",
  "acceptance_criteria": [
    "User can sign up with email/password",
    "User can log in and receive a session token",
    "Invalid credentials return 401"
  ],
  "dependencies": [],
  "completed_by_session": null
}
```

Valid `status` values: `pending`, `in-progress`, `completed`, `blocked`, `split`.

### `.flywheel/init.sh` and `.flywheel/init.ps1`

Auto-detect the project type and generate both scripts. See Section 4 for the detection logic.

### `.flywheel/claude-progress.jsonl`

Create as an empty file. The Coding Agent appends one JSON object per session:

```json
{"timestamp":"2026-03-23T14:30:00Z","feature_id":"feat-001","feature_title":"User authentication","status":"completed","changes":["Added auth module (src/auth/)","Login/signup endpoints","JWT middleware"],"tests":{"unit":12,"e2e":1,"all_passing":true},"next_priority":"feat-002","notes":"Used bcrypt for password hashing, tokens expire in 24h"}
```

Log rotation: keep the last 50 entries in the active file. When exceeding 50, archive older entries to `.flywheel/claude-progress-archive.jsonl`.

---

## 4. Init Script Generation

Detect the project type by checking for marker files at the project root. Use the first match.

| File found | Project type | Unix command (`init.sh`) | PowerShell command (`init.ps1`) |
|---|---|---|---|
| `package.json` | Node.js | `npm install && npm start` | `npm install; npm start` |
| `requirements.txt` | Python | `pip install -r requirements.txt` | `pip install -r requirements.txt` |
| `Cargo.toml` | Rust | `cargo build && cargo run` | `cargo build; cargo run` |
| `go.mod` | Go | `go build ./...` | `go build ./...` |
| (fallback) | Unknown | `echo "Configure init.sh for your project"` | `Write-Host "Configure init.ps1 for your project"` |

### Generated `init.sh` template

```bash
#!/usr/bin/env bash
set -euo pipefail

# Auto-generated by flywheel Initializer
# Project type: [detected type]
# Edit this file to customize your bootstrap sequence

[detected unix command]
```

### Generated `init.ps1` template

```powershell
# Auto-generated by flywheel Initializer
# Project type: [detected type]
# Edit this file to customize your bootstrap sequence

$ErrorActionPreference = "Stop"

[detected powershell command]
```

Both scripts should be marked executable after generation (`chmod +x .flywheel/init.sh` on Unix).

---

## 5. Initial Commit

After generating all artifacts, commit them as a clean baseline:

```bash
# 1. Create directory (already done during artifact generation)
mkdir -p .flywheel

# 2. Write all artifacts
#    - .flywheel/flywheel-config.json
#    - .flywheel/feature-checklist.json
#    - .flywheel/init.sh
#    - .flywheel/init.ps1
#    - .flywheel/claude-progress.jsonl

# 3. Stage all flywheel files
git add .flywheel/

# 4. Commit
git commit -m "chore: initialize flywheel"
```

This commit creates the clean baseline that all subsequent Coding Agent sessions build on.
