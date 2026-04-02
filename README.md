# Flywheel

**Zero-cost session handoffs for long-running AI coding agents.**

Flywheel is a Claude Code plugin that breaks large projects into one-feature-per-session cycles. Each session picks up where the last left off, implements one feature, reviews it through a 4-layer pipeline, and commits merge-ready code with a machine-readable handoff for the next session.

```
Session 1                    Session 2                    Session 3
┌──────────────────┐        ┌──────────────────┐        ┌──────────────────┐
│ Read handoff     │───────▶│ Read handoff     │───────▶│ Read handoff     │
│ Pick feat-001    │        │ Pick feat-002    │        │ Pick feat-003    │
│ Implement        │        │ Implement        │        │ Implement        │
│ Review (4-layer) │        │ Review (4-layer) │        │ Review (4-layer) │
│ Commit + handoff │───────▶│ Commit + handoff │───────▶│ Commit + handoff │
└──────────────────┘        └──────────────────┘        └──────────────────┘
     feat-001 ✅                 feat-002 ✅                 feat-003 ✅
```

## Why

AI coding agents burn through their context window on large projects. The usual result: half-finished features, skipped tests, lost context between sessions. Flywheel fixes this with three rules:

1. **One feature per session.** No scope creep. Context stays focused.
2. **Merge-ready or revert.** No WIP commits. Every session leaves the codebase clean.
3. **Machine-readable handoff.** The next session knows exactly what happened and what's next.

### Benefits

- **Zero-context-loss handoffs.** Session dies mid-project? No problem. The machine-readable handoff log tells the next session exactly what was done, what failed, and what's next. No manual briefing needed.
- **Stateless sessions, persistent progress.** Once the feature checklist exists, every session is disposable. Open, close, crash — it doesn't matter. The next session reads the checklist, picks up the next pending feature, and keeps going.
- **Scope discipline prevents context blowout.** One feature per session. AI agents love to scope-creep until they burn through the context window and produce half-finished work. Flywheel enforces focus: implement one thing, review it, commit merge-ready code, move on.
- **4-layer review catches what single-model can't.** Cleanup (author proofreads) → Peer review (fresh agent) → Cross-model (different AI catches blind spots) → E2E (real verification). Each layer catches what the previous one misses.
- **Dynamic feature management between sessions.** Add, revise, reprioritize, split, or remove features at any time with `/flywheel:features`. The project plan evolves with you — no need to re-initialize or restart.
- **Pluggable, not locked-in.** Every spoke (planning, multi-agent, review) has a zero-dependency built-in default. Install superpowers, codex, playwright as you need them. Works with one tool or all four.
- **Auditable by design.** Every session ends with a compliance table showing exactly what ran, what was skipped, and why. The handoff log is a complete audit trail of every feature implemented across the project.

## Quick start

### Install

**Add the marketplace and install the plugin:**

```bash
/plugin marketplace add romanticamaj/flywheel
/plugin install flywheel@flywheel-marketplace
```

**For development / testing (temporary, current session only):**

```bash
git clone https://github.com/romanticamaj/flywheel.git ~/.claude/plugins/flywheel
claude --plugin-dir ~/.claude/plugins/flywheel
```

### Initialize (once per project)

```
/flywheel:init
```

Flywheel detects your installed tools, lets you choose per spoke, and creates `.flywheel/` with:

```
.flywheel/
├── flywheel-config.json      # Tool choices + rules
├── feature-checklist.json    # Prioritized features with acceptance criteria
├── init.sh / init.ps1        # Auto-detected bootstrap scripts
└── claude-progress.jsonl     # Handoff log (grows each session)
```

### Run (each session)

```
/flywheel:relay
```

The agent follows a **9-step loop**:

| Step | What happens |
|------|-------------|
| 1. Validate config | Read `.flywheel/flywheel-config.json`, verify tools |
| 2. Read handoff | Last 20 entries from handoff log + `git log` |
| 3. Read checklist | Pick highest-priority uncompleted feature |
| 4. Bootstrap | Run `init.sh` to start dev environment |
| 5. Smoke test | Confirm baseline is healthy before touching code |
| 6. Plan | Design the implementation approach |
| 7. Implement | One feature only, with tests |
| 8. Review | 4-layer pipeline: cleanup → peer review → cross-model → E2E |
| 9. Commit + handoff | Git commit, append handoff entry, update checklist |

Every session ends with a compliance table:

```
SESSION FLOW SUMMARY — feat-001: Health endpoint
┌────┬──────────────────────┬──────────────┬──────────────────────────────────┬──────────┐
│ #  │ Stage                │ Configured   │ Actual                           │ Status   │
├────┼──────────────────────┼──────────────┼──────────────────────────────────┼──────────┤
│ 1  │ Validate config      │ —            │ Config parsed, all tools valid   │ ✅ OK    │
│ 2  │ Read handoff         │ —            │ Empty log (first session)        │ ✅ OK    │
│ 3  │ Read checklist       │ —            │ feat-001 selected (priority 1)   │ ✅ OK    │
│ 4  │ Bootstrap            │ init.sh      │ npm install                      │ ✅ OK    │
│ 5  │ Smoke test           │ —            │ npm test + npm run build pass    │ ✅ OK    │
│ 6  │ Plan                 │ plan-w-files │ task_plan.md created              │ ✅ OK    │
│ 7  │ Implement            │ superpowers  │ /health with uptime + 5 tests    │ ✅ OK    │
│ 8a │ Review: cleanup      │ /simplify    │ superpowers:/simplify             │ ✅ OK    │
│ 8b │ Review: peer-review  │ peer-reviewer│ superpowers peer-reviewer (agent) │ ✅ OK    │
│ 8c │ Review: cross-model  │ codex:review │ codex:review (OpenAI)             │ ✅ OK    │
│ 8d │ Review: e2e          │ playwright   │ Playwright browser verification   │ ✅ OK    │
│ 9  │ Commit + handoff     │ —            │ Committed + handoff written      │ ✅ OK    │
└────┴──────────────────────┴──────────────┴──────────────────────────────────┴──────────┘
RESULT: 13/13 stages OK
```

## Architecture

Flywheel has two phases and three pluggable spokes:

```
                    ┌─────────────────────────────────────────┐
                    │              Flywheel Hub               │
                    │                                         │
                    │  Phase 1: Initializer (run once)        │
                    │  Phase 2: Coding Agent (run N times)    │
                    │                                         │
                    └──────┬──────────┬──────────┬────────────┘
                           │          │          │
                    ┌──────▼───┐ ┌────▼─────┐ ┌──▼───────────┐
                    │ Planning │ │ Multi-   │ │   Review     │
                    │  Spoke   │ │ Agent    │ │  Pipeline    │
                    │          │ │ Spoke    │ │              │
                    │ built-in │ │ built-in │ │ 4 layers:    │
                    │ planwf   │ │ worktree │ │  cleanup     │
                    │ openspec │ │ gstack   │ │  peer-review │
                    │ superpwr │ │ superpwr │ │  cross-model │
                    └──────────┘ └──────────┘ │  e2e         │
                                              └──────────────┘
```

Each spoke is independent. All have a **built-in zero-dependency default** and optional framework slots:

| Spoke | Built-in default | Optional tools |
|-------|-----------------|----------------|
| **Planning** | Claude generates `feature-checklist.json` directly | planning-with-files, OpenSpec, superpowers |
| **Multi-Agent** | Claude Code `--worktree` + `Agent` tool | gstack Conductor, superpowers |
| **Review** | Subagent peer review + test suite smoke test | gstack, superpowers, codex, Playwright, Gemini CLI |

### Recommended stack

The author's recommended configuration for maximum coverage:

```
┌──────────────────┬──────────────────────────┬──────────────────────────────────┐
│ Spoke            │ Tool                     │ Why                              │
├──────────────────┼──────────────────────────┼──────────────────────────────────┤
│ Planning         │ planning-with-files      │ File-based plans with progress   │
│ Multi-agent      │ superpowers              │ Parallel agent dispatch          │
│ Cleanup          │ superpowers /simplify    │ Author cleanup — dead code, etc  │
│ Peer review      │ superpowers peer-reviewer│ Fresh agent — bugs, security     │
│ Cross-model      │ codex:review             │ Different model catches biases   │
│ E2E              │ Playwright               │ Real browser verification        │
└──────────────────┴──────────────────────────┴──────────────────────────────────┘
```

**Install the recommended stack:**

```bash
# 1. superpowers — multi-agent, cleanup, peer-review
#    Source: https://github.com/obra/superpowers
/plugin install superpowers@claude-plugins-official

# 2. planning-with-files — file-based planning (task_plan.md, progress tracking)
#    Source: https://github.com/OthmanAdi/planning-with-files
npx skills add OthmanAdi/planning-with-files --skill planning-with-files -g

# 3. codex — cross-model review (requires OpenAI/ChatGPT account)
#    Source: https://github.com/openai/codex-plugin-cc
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/codex:setup

# 4. playwright — real browser E2E verification (Claude Code plugin)
#    Source: https://github.com/anthropics/claude-plugins-public/tree/main/external_plugins/playwright
/plugin install playwright@claude-plugins-official
```

Then run `/flywheel:init` — the initializer will auto-detect all four and pre-select them.

> **Minimal setup:** If you only install one thing, install **superpowers**. It covers multi-agent, cleanup, and peer review. Add **planning-with-files** for auditable plan artifacts. Add **codex** for cross-model bias detection. Add **Playwright** for real browser E2E instead of smoke tests.

## The handoff log

The handoff log (`claude-progress.jsonl`) is the flywheel's memory. Each session appends one entry:

```json
{
  "timestamp": "2026-03-27T00:00:00Z",
  "feature_id": "feat-001",
  "feature_title": "Health endpoint",
  "status": "completed",
  "changes": [
    "Added /health endpoint with uptime tracking",
    "Added 5 integration tests"
  ],
  "tests": { "unit": 5, "e2e": 5, "all_passing": true },
  "review": {
    "cleanup": "built-in",
    "peer-review": "built-in (peer-reviewer subagent)",
    "cross-model": "skipped (disabled)",
    "e2e": "npm test + npm run build"
  },
  "next_priority": "feat-002",
  "notes": "Server exports module without auto-starting via require.main guard."
}
```

The next session reads this log to understand context, skips completed features, and picks up `feat-002`. No context is lost. No work is repeated.

## Feature checklist

Machine-readable JSON, not markdown. Agents can't cheat the structure.

```json
{
  "version": 1,
  "features": [
    {
      "id": "feat-001",
      "title": "Health endpoint",
      "priority": 1,
      "status": "completed",
      "acceptance_criteria": [
        "GET /health returns 200 with JSON body containing status and uptime"
      ],
      "dependencies": [],
      "completed_by_session": "2026-03-27T00:00:00Z"
    },
    {
      "id": "feat-002",
      "title": "User list endpoint",
      "priority": 2,
      "status": "pending",
      "acceptance_criteria": [
        "GET /users returns 200 with JSON array of user objects (id, name, email)"
      ],
      "dependencies": [],
      "completed_by_session": null
    }
  ]
}
```

## The 4-layer review pipeline

Each layer catches what the previous one misses:

| Layer | Catches | Tools |
|-------|---------|-------|
| **1. Cleanup** | Dead code, duplication, unnecessary complexity | superpowers /simplify |
| **2. Peer review** | Logic bugs, security issues, convention violations | gstack /review, superpowers peer-reviewer |
| **3. Cross-model** | Systematic biases of the authoring model | **codex:review** (primary), gstack /codex, Gemini CLI |
| **4. E2E** | Integration failures, broken UI, API contract violations | gstack /qa, Playwright |

Which layers run depends on the active **profile** — see [Stage profiles](#stage-profiles). Default (`standard`): layers 2 + 4. All four on `full`.

## Stage profiles

Profiles control which review layers run per session — optimizing token usage without sacrificing quality where it matters.

```
┌──────────┬──────────┬─────────────┬──────────────┬──────────────┬──────────┐
│ Profile  │ Planning │ Cleanup     │ Peer review  │ Cross-model  │ E2E      │
├──────────┼──────────┼─────────────┼──────────────┼──────────────┼──────────┤
│ full     │ ✅       │ ✅          │ ✅ full      │ ✅           │ ✅       │
│ standard │ ✅       │ —           │ ✅ top 5     │ —            │ ✅       │
│ light    │ ✅       │ —           │ ✅ verdict   │ —            │ —        │
│ draft    │ ✅       │ —           │ —            │ —            │ —        │
└──────────┴──────────┴─────────────┴──────────────┴──────────────┴──────────┘
```

- **full** — all layers, full verbosity. For high-priority or security-sensitive features.
- **standard** — peer review (top 5 issues) + E2E. Good default for most features.
- **light** — peer review (pass/fail verdict only). Quick validation for low-priority work.
- **draft** — planning only. For rapid prototyping — no review overhead.

### Adaptive mode

Set `"profile.default": "adaptive"` in config (the default). The agent auto-selects based on feature priority:

| Feature priority | Profile | Rationale |
|-----------------|---------|-----------|
| 1–2 (high) | full | Core features get maximum scrutiny |
| 3–5 (medium) | standard | Balanced coverage for typical work |
| 6+ (low) | light | Fast validation for minor features |

Bump rules override adaptive selection: first feature in the project always gets `full`, security-sensitive features always get `full`, and having a cross-model tool installed bumps one tier up.

The agent presents the recommended profile at the start of each relay session — the user can accept or override.

## Rules

| Rule | Why |
|------|-----|
| **One feature per session** | Context stays focused. No scope creep. |
| **Merge-ready or revert** | No WIP commits. Codebase is always clean. |
| **Attempt before fallback** | Configured tools must be tried before substituting. |
| **Ask before skipping** | Agent can't silently skip review layers. |
| **Compliance table required** | Every session ends with an accountability record. |

## Feature management

Features are dynamic — add, revise, reprioritize, split, or remove them between relay sessions:

```
/flywheel:features          # Add, revise, reprioritize, split, remove features
/flywheel:features-list     # Read-only view with progress summary
```

## Testing

The E2E test suite invokes `claude -p` against a mock Node.js project, validating artifacts, schemas, and behavior at each flywheel stage.

```bash
# Run all 10 tests (~31 assertions)
./tests/run-tests.sh --test all

# Run by phase
./tests/run-tests.sh --test init              # Initializer artifacts
./tests/run-tests.sh --test relay             # 9-step coding agent loop
./tests/run-tests.sh --test continuity        # Multi-session handoff
./tests/run-tests.sh --test features          # Add, revise, split, remove, integrity
./tests/run-tests.sh --test features-list     # Read-only display

# Run individual feature tests
./tests/run-tests.sh --test features-add
./tests/run-tests.sh --test features-revise
./tests/run-tests.sh --test features-split
./tests/run-tests.sh --test features-remove
```

| Test | Validates |
|------|-----------|
| **1. Init** | `.flywheel/` directory, config schema, checklist schema, init scripts, git commit |
| **2. Relay** | Handoff log, JSONL schema, checklist update, feature commit, compliance output |
| **3. Continuity** | Handoff growth, different feature picked, no duplicate work |
| **4. Features Add** | Count increased, unique IDs, valid schema, correct titles |
| **5. Features Revise** | Criteria expanded, other features untouched, count stable |
| **6. Features Split** | Parent marked split, sub-features valid, no duplicate IDs |
| **7. Features Remove** | Target gone, schema intact, IDs not renumbered, valid JSON |
| **8. Source Metadata** | Config source field preserved through all operations |
| **9. Integrity** | Full checklist validation: version, types, statuses, constraints |
| **10. Features List** | Output contains IDs/titles/statuses, read-only verified |

**Requirements:** `claude` CLI (authenticated), `python3`, `git`. Each test call costs ~$0.30–$1.00 (Sonnet, $1.00 cap).

## Compared to alternatives

| Project | Approach | What flywheel adds |
|---------|----------|--------------------|
| **Continuous-Claude** (3.6k stars) | Lifecycle hooks for auto-handoff | Opinionated workflow: scope rules, review pipeline, compliance tracking |
| **cli-continues** (977 stars) | Cross-tool portable context export | Structured feature checklist + acceptance criteria |
| **HANDOFF.md pattern** | Freeform markdown handoff | Machine-readable JSON, enforced schema, log rotation |
| **LangGraph checkpointing** | Framework-level state persistence | Agent-level session protocol, works with any Claude Code setup |

## Contributing

Issues and PRs welcome at [github.com/romanticamaj/flywheel](https://github.com/romanticamaj/flywheel).

## License

MIT
