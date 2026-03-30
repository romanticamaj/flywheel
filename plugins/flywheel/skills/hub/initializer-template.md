# Flywheel — Initializer Template

This is a reference template for the Initializer phase of the flywheel protocol. The hub skill (`flywheel/SKILL.md`) cross-references this document when running Phase 1 setup on a new project.

---

## 1. Runtime Detection Algorithm

Execute these 7 steps in order at Initializer startup.

### Step 1: Scan Claude Code Skills List

Check the active Claude Code skills list for known skill names:

| Spoke | Skill names to look for |
|---|---|
| Planning | `planning-with-files`, `superpowers` (brainstorming / writing-plans) |
| Multi-agent | `gstack` (Conductor commands), `superpowers` (dispatching-parallel-agents, subagent-driven-development) |
| Review — self-review | `superpowers` (code-simplifier / /simplify) |
| Review — code-review | `gstack` (/review), `superpowers` (code-reviewer) |
| Review — cross-model | `gstack` (/codex) |
| Review — E2E | `gstack` (/qa) |

### Step 2: Check node_modules for npm Packages

Search both local and global installations:

```
# Local
ls node_modules/openspec 2>/dev/null
ls node_modules/playwright 2>/dev/null

# Global
npm list -g openspec --depth=0 2>/dev/null
npm list -g playwright --depth=0 2>/dev/null
```

| Package | Maps to spoke |
|---|---|
| `openspec` | Planning |
| `playwright` | Review — E2E |

### Step 3: Check PATH for CLI Tools

```
which gemini 2>/dev/null || where gemini 2>NUL
which codex 2>/dev/null || where codex 2>NUL
which playwright 2>/dev/null || where playwright 2>NUL
```

| CLI tool | Maps to spoke |
|---|---|
| `gemini` | Review — cross-model |
| `codex` | Review — cross-model |
| `playwright` | Review — E2E |

### Step 4: Build Available-Tools Map

Merge results from Steps 1-3 into a single map:

```json
{
  "planning": ["planning-with-files", "openspec", "superpowers"],
  "multi_agent": ["gstack", "superpowers", "claude-code-native"],
  "review": {
    "self-review": ["superpowers:/simplify"],
    "code-review": ["gstack:/review", "superpowers:code-reviewer"],
    "cross-model": ["gstack:/codex", "gemini-cli"],
    "e2e": ["gstack:/qa", "playwright"]
  }
}
```

Only include tools that were actually detected. `claude-code-native` is always present for multi-agent.

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
> | 2 | ✅/⬜ | **superpowers** | Brainstorming + writing-plans skills | Already a Claude Code plugin — install via `/plugin install superpowers` |
> | 3 | ✅/⬜ | **OpenSpec** | Structured proposal.md + specs/ directory | `npm install -g openspec` |
> | 4 | ✅ | **built-in** | Claude generates feature-checklist.json directly, no dependencies | Always available |

#### Multi-Agent

> **Multi-agent** — coordinates parallel agents working on separate features.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gstack** | Conductor for parallel sprints + /plan-ceo-review, /plan-eng-review, /review, /qa, /ship | `git clone` gstack repo, add as plugin |
> | 2 | ✅/⬜ | **superpowers** | dispatching-parallel-agents, subagent-driven-development | Already a Claude Code plugin — install via `/plugin install superpowers` |
> | 3 | ✅ | **claude-code-native** | Built-in `--worktree` isolation + `Agent` tool, no dependencies | Always available |

#### Review — Self-review

> **Self-review** — catches dead code, duplication, unnecessary complexity.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **superpowers /simplify** | Code simplifier agent | Already a Claude Code plugin — install via `/plugin install superpowers` |
> | 2 | ✅/⬜ | **gstack /simplify** | gstack code simplifier | Add gstack as plugin |
> | 3 | ✅ | **built-in** | Manual diff review prompt | Always available |

#### Review — Code review

> **Code review** — catches logic bugs, security issues, convention violations.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gstack /review** | Pre-landing PR review with SQL safety, trust boundary analysis | Add gstack as plugin |
> | 2 | ✅/⬜ | **superpowers code-reviewer** | Code reviewer subagent | Already a Claude Code plugin — install via `/plugin install superpowers` |
> | 3 | ✅ | **built-in** | Spawn a code-reviewer subagent with built-in prompt | Always available |

#### Review — Cross-model

> **Cross-model** — catches systematic biases and blind spots of the authoring model.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gemini-cli** | Gemini CLI for second-opinion review | Install: `npm install -g @anthropic-ai/gemini-cli` or check if `gemini` is in PATH |
> | 2 | ✅/⬜ | **gstack /codex** | OpenAI Codex CLI wrapper for adversarial review | Add gstack as plugin |
> | 3 | ✅/⬜ | **codex-cli** | Codex CLI directly | Install: `npm install -g @openai/codex` or check if `codex` is in PATH |
> | 4 | — | **Skip** | Disable this layer | — |

#### Review — E2E

> **E2E verification** — proves the feature actually works end-to-end.
>
> | # | Status | Tool | Description | Install |
> |---|--------|------|-------------|---------|
> | 1 | ✅/⬜ | **gstack /qa** | Systematic QA testing with headless browser, finds + fixes bugs | Add gstack as plugin |
> | 2 | ✅/⬜ | **Playwright** | Browser automation for E2E tests | `npm install playwright` |
> | 3 | ✅ | **built-in** | Run init script + test suite + health check | Always available |

### Install-on-demand flow

If the user picks a tool marked ⬜ (not installed):

1. Show the install command.
2. Ask: "Want me to install it now, or proceed with a different option?"
3. If yes — run the install command, verify it worked, then continue.
4. If no — ask them to pick another option.

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
| `review.layers` | string[] | Fixed: `["self-review", "code-review", "cross-model", "e2e"]` |
| `review.tools` | object | Per-layer tool choice; `null` means layer is skipped |
| `review.alternatives` | object | Per-layer list of known tools |
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

Valid `status` values: `pending`, `in-progress`, `completed`, `blocked`.

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
