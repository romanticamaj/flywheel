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

## Quick start

### Install

```bash
# Clone the plugin
git clone https://github.com/romanticamaj/flywheel.git ~/.claude/plugins/flywheel
```

Then add it to your Claude Code session:

```bash
claude --plugin-dir ~/.claude/plugins/flywheel
```

Or add it permanently to your project's `.claude/settings.json`:

```json
{
  "pluginDirs": ["~/.claude/plugins/flywheel"]
}
```

### Initialize (once per project)

```
> I want to start a new project with flywheel.
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
> Start a flywheel coding agent session.
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
| 8. Review | 4-layer pipeline: self-review → code review → cross-model → E2E |
| 9. Commit + handoff | Git commit, append handoff entry, update checklist |

Every session ends with a compliance table:

```
SESSION COMPLIANCE — feat-001: Health endpoint
┌────┬──────────────────────┬──────────────┬──────────────────────────────────┬──────────┐
│ #  │ Stage                │ Configured   │ Actual                           │ Status   │
├────┼──────────────────────┼──────────────┼──────────────────────────────────┼──────────┤
│ 1  │ Validate config      │ —            │ Config parsed, all tools valid   │ ✅ OK    │
│ 2  │ Read handoff         │ —            │ Empty log (first session)        │ ✅ OK    │
│ 3  │ Read checklist       │ —            │ feat-001 selected (priority 1)   │ ✅ OK    │
│ 4  │ Bootstrap            │ init.sh      │ npm install                      │ ✅ OK    │
│ 5  │ Smoke test           │ —            │ npm test + npm run build pass    │ ✅ OK    │
│ 6  │ Plan                 │ built-in     │ Approach outlined                │ ✅ OK    │
│ 7  │ Implement            │ —            │ /health with uptime + 5 tests    │ ✅ OK    │
│ 8a │ Review: self-review  │ built-in     │ Manual diff review               │ ✅ OK    │
│ 8b │ Review: code-review  │ built-in     │ Code reviewer subagent           │ ✅ OK    │
│ 8c │ Review: cross-model  │ null         │ Skipped (disabled)               │ ✅ OK    │
│ 8d │ Review: e2e          │ built-in     │ npm test + npm run build         │ ✅ OK    │
│ 9  │ Commit + handoff     │ —            │ Committed + handoff written      │ ✅ OK    │
└────┴──────────────────────┴──────────────┴──────────────────────────────────┴──────────┘
RESULT: 15/15 stages OK
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
                    │ planwf   │ │ worktree │ │  self-review │
                    │ openspec │ │ gstack   │ │  code-review │
                    │ superpwr │ │ superpwr │ │  cross-model │
                    └──────────┘ └──────────┘ │  e2e         │
                                              └──────────────┘
```

Each spoke is independent. All have a **built-in zero-dependency default** and optional framework slots:

| Spoke | Built-in default | Optional tools |
|-------|-----------------|----------------|
| **Planning** | Claude generates `feature-checklist.json` directly | planning-with-files, OpenSpec, superpowers |
| **Multi-Agent** | Claude Code `--worktree` + `Agent` tool | gstack Conductor, superpowers |
| **Review** | Subagent code review + test suite smoke test | gstack, superpowers, Playwright, Gemini CLI |

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
    "self-review": "built-in",
    "code-review": "built-in (code-reviewer subagent)",
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
| **1. Self-review** | Dead code, duplication, unnecessary complexity | superpowers /simplify |
| **2. Code review** | Logic bugs, security issues, convention violations | gstack /review, superpowers code-reviewer |
| **3. Cross-model** | Systematic biases of the authoring model | Gemini CLI, gstack /codex |
| **4. E2E** | Integration failures, broken UI, API contract violations | gstack /qa, Playwright |

Minimum required: layers 2 + 4. All four recommended when tools are available.

## Rules

| Rule | Why |
|------|-----|
| **One feature per session** | Context stays focused. No scope creep. |
| **Merge-ready or revert** | No WIP commits. Codebase is always clean. |
| **Attempt before fallback** | Configured tools must be tried before substituting. |
| **Ask before skipping** | Agent can't silently skip review layers. |
| **Compliance table required** | Every session ends with an accountability record. |

## Testing

Run the E2E test suite against a mock project:

```bash
# Run all tests (init → relay → continuity)
./tests/run-tests.sh

# Run specific test
./tests/run-tests.sh --test init
./tests/run-tests.sh --test relay
./tests/run-tests.sh --test continuity
```

The tests invoke Claude Code in print mode against a mock Node.js project with three features, verifying that flywheel creates artifacts, follows the 9-step loop, and maintains session continuity across multiple invocations.

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
