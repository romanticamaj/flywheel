# Token Efficiency: Stage Profiles + Subagent Isolation + Adaptive Mode

**Date:** 2026-04-01
**Status:** Implemented (v1.7.0)

## Problem

Running all 4 review layers every session consumes excessive tokens. Low-priority features don't need the same scrutiny as core features.

## Solution

Three mechanisms working together:

### 1. Stage Profiles

Four profiles control which review layers run and peer-review verbosity:

| Profile | Cleanup | Peer review | Cross-model | E2E | Use case |
|---------|---------|-------------|-------------|-----|----------|
| full | yes | full report | yes | yes | High-priority, security-sensitive |
| standard | no | top 5 issues | no | yes | Most features |
| light | no | verdict only | no | no | Low-priority features |
| draft | no | skip | no | no | Rapid prototyping |

Planning always runs in all profiles.

### 2. Subagent Isolation for Peer Review

Peer review runs as an isolated subagent returning structured JSON:

```json
{
  "verdict": "pass|fail|conditional",
  "summary": "...",
  "issues": [{ "severity": "critical|important|minor", "file": "...", "message": "..." }],
  "issue_counts": { "critical": 0, "important": 1, "minor": 3 }
}
```

Verbosity levels (`full`, `top5`, `verdict`) control how much detail returns to the main agent, saving tokens on standard/light profiles.

Fail escalation: if verdict is `fail` on `verdict`-only mode, automatically re-runs with `top5` to surface actionable issues.

### 3. Adaptive Mode

When `profile.default` is `"adaptive"`, auto-selects profile based on feature priority:

- Priority 1-2 → full
- Priority 3-5 → standard
- Priority 6+ → light

Bump rules override: first feature → full, security-sensitive → full, cross-model tool installed → +1 tier.

The agent presents the recommendation at relay start; user can accept or override.

## Config Schema

```json
{
  "profile": {
    "default": "adaptive",
    "adaptive_rules": { "1-2": "full", "3-5": "standard", "6+": "light" },
    "bump_rules": { "first_feature": "full", "security_sensitive": "full", "has_dependencies": "+1 tier", "was_blocked": "full", "has_cross_model_tool": "+1 tier" }
  },
  "review": {
    "profiles": {
      "full":     { "cleanup": true,  "peer-review": "full",    "cross-model": true,  "e2e": true  },
      "standard": { "cleanup": false, "peer-review": "top5",    "cross-model": false, "e2e": true  },
      "light":    { "cleanup": false, "peer-review": "verdict", "cross-model": false, "e2e": false },
      "draft":    { "cleanup": false, "peer-review": false,     "cross-model": false, "e2e": false }
    }
  }
}
```

## Files Changed

- `plugins/flywheel/skills/hub/coding-agent-template.md` — Step 3b (profile selection), Step 8 (profile-aware dispatch, subagent isolation)
- `plugins/flywheel/skills/hub/initializer-template.md` — Config schema with profile section
- `plugins/flywheel/skills/hub/SKILL.md` — Config reference updated
- `plugins/flywheel/skills/review-pipeline/SKILL.md` — Layer rename
- `plugins/flywheel/skills/multi-agent/SKILL.md` — Layer rename
- `plugins/flywheel/commands/relay.md` — Step 8 description updated
- `README.md` — Stage profiles section, layer rename throughout
