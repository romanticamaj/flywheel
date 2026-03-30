---
name: planning
description: Use when setting up project planning for flywheel — defines the planning contract and framework slots for planning-with-files, OpenSpec, and superpowers
---

# Planning Spoke

Defines the contract that any planning tool must satisfy to work with flywheel, plus framework slots for three supported tools. When no external tool is installed, the built-in default generates `feature-checklist.json` directly.

## Contract

A planning tool must produce:

- A **prioritized list of work items** readable by the Coding Agent
- **Enough detail per item** for a fresh session to implement without guessing

All output is normalized into `feature-checklist.json` regardless of which tool produces it.

## Default (Built-in, Zero Dependencies)

The Initializer prompts the user to describe features, then Claude generates `.flywheel/feature-checklist.json` directly. No external tool required.

## Framework Slots

| Tool | Install | Contract Mapping |
|------|---------|-----------------|
| **planning-with-files** | `npx skills add OthmanAdi/planning-with-files --skill planning-with-files -g` | `task_plan.md` phases → checklist items; `findings.md` → acceptance criteria |
| **OpenSpec** | `npm install openspec` | `/opsx:propose` generates `proposal.md` + `specs/` → checklist items with full specs |
| **superpowers** | Already a Claude Code plugin | brainstorming → writing-plans → plan file on disk → checklist extraction |

## Detection

| Tool | How to Detect |
|------|--------------|
| planning-with-files | `planning-with-files` in installed skills list |
| OpenSpec | `openspec` in `node_modules` or global npm |
| superpowers | superpowers in Claude Code plugins |

## feature-checklist.json Reference

Path: `.flywheel/feature-checklist.json`

### Schema

```json
{
  "version": 1,
  "features": [
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
  ]
}
```

### Field Notes

| Field | Description |
|-------|------------|
| `version` | Schema version wrapper for future migration. Currently `1`. |
| `status` | Valid values: `pending`, `in-progress`, `completed`, `blocked` |
| `dependencies` | Array of feature IDs. Used for ordering — blocked features are skipped. |
| `completed_by_session` | `null` initially. Set to session timestamp (ISO 8601) on completion. |
| `priority` | Integer. Lower number = higher priority. Coding Agent picks highest priority uncompleted item. |

### Design Decisions

- **JSON not markdown** — agents cheat with markdown structure, producing inconsistent formats. JSON is machine-parseable and enforceable.
- **Version wrapper** — enables schema migration without breaking existing checklists.
- **`completed_by_session`** — provides traceability back to which session completed a feature.
- **Dependencies array** — enables the Coding Agent to skip items whose dependencies are not yet completed.
