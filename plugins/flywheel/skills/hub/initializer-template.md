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

Present these prompts to the user during Initializer setup. Replace `[detected]` with the actual tools found in Step 4.

### Planning Spoke

**Multiple tools detected:**

> I detected the following planning tools: [detected].
>
> Which would you like to use for planning?
> 1. **[detected tool 1]**
> 2. **[detected tool 2]**
> 3. **built-in** (Claude generates feature-checklist.json directly, no dependencies)
>
> Enter your choice (number or name):

**One tool detected:**

> I detected **[tool name]** for planning. Would you like to use it, or stick with the built-in default?
> 1. **[tool name]**
> 2. **built-in** (Claude generates feature-checklist.json directly, no dependencies)

**No tools detected:**

> No external planning tools detected. Using **built-in** planning (Claude generates feature-checklist.json directly).
>
> For richer planning, you can install one of these:
> - **planning-with-files:** `npx skills add OthmanAdi/planning-with-files --skill planning-with-files -g`
> - **OpenSpec:** `npm install openspec`
>
> Want to proceed with built-in for now? (Y/n)

### Multi-Agent Spoke

**Multiple tools detected:**

> I detected the following multi-agent coordination tools: [detected].
>
> Which would you like to use for multi-agent coordination?
> 1. **[detected tool 1]**
> 2. **[detected tool 2]**
> 3. **claude-code-native** (built-in `--worktree` isolation + `Agent` tool, no dependencies)
>
> Enter your choice (number or name):

**One tool detected:**

> I detected **[tool name]** for multi-agent coordination. Would you like to use it, or stick with Claude Code native?
> 1. **[tool name]**
> 2. **claude-code-native** (built-in `--worktree` isolation + `Agent` tool, no dependencies)

**No tools detected (only native available):**

> Using **claude-code-native** for multi-agent coordination (built-in `--worktree` isolation + `Agent` tool).
>
> For richer coordination, you can install:
> - **gstack:** provides Conductor for parallel sprints, /plan-ceo-review, /plan-eng-review, /review, /qa, /ship
> - **superpowers:** provides dispatching-parallel-agents, subagent-driven-development
>
> Want to proceed with claude-code-native for now? (Y/n)

### Review Spoke (per layer)

Prompt separately for each review layer:

**Self-review layer:**

> **Self-review layer** — catches dead code, duplication, unnecessary complexity.
>
> Detected tools: [detected or "none"].
> 1. **[detected tool]** (if any)
> 2. **built-in** (manual review prompt)
>
> For richer self-review, you can install:
> - **superpowers /simplify:** already a Claude Code plugin

**Code-review layer:**

> **Code-review layer** — catches logic bugs, security issues, convention violations.
>
> Detected tools: [detected or "none"].
> 1. **[detected tool 1]** (if any)
> 2. **[detected tool 2]** (if any)
> 3. **built-in** (manual review prompt)
>
> For richer code review, you can install:
> - **gstack /review**
> - **superpowers code-reviewer**

**Cross-model layer:**

> **Cross-model layer** — catches systematic biases and blind spots of the authoring model.
>
> Detected tools: [detected or "none"].
> 1. **[detected tool 1]** (if any)
> 2. **[detected tool 2]** (if any)
> 3. **Skip this layer** (no built-in default available)
>
> To enable cross-model review, install one of:
> - **Gemini CLI:** `gemini` command in PATH
> - **Codex CLI:** `codex` command in PATH
> - **gstack /codex**

**E2E verification layer:**

> **E2E verification layer** — catches integration failures, broken UI, API contract violations.
>
> Detected tools: [detected or "none"].
> 1. **[detected tool 1]** (if any)
> 2. **[detected tool 2]** (if any)
> 3. **built-in** (run init script + test suite + health check)
>
> For richer E2E testing, you can install:
> - **Playwright:** `npm install playwright` or check if `playwright` is in PATH
> - **gstack /qa**

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
