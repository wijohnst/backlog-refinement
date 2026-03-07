# Backlog Refinement System Design

## Overview

A token-efficient backlog refinement system that:
- Tracks refinement state per story to avoid redundant LLM calls
- Uses bash scripts for deterministic, fast backlog analysis
- Batches multiple stories into single Claude calls for efficiency
- Maintains audit trail of app state at refinement time to detect staleness
- Leverages GitHub labels as source of truth for refinement triggers

---

## Core Problems Solved

### 1. Token Efficiency
**Problem**: Current approach dumps entire backlog + ADRs + plan docs into every prompt, even for stories that don't need refinement.

**Solution**: 
- Bash scripts determine which stories need refinement without LLM calls
- Only load context for stories that actually need work
- Batch multiple stories into single Claude call

**Result**: ~80% reduction in token spend for typical backlog checks.

### 2. Stale Assumptions
**Problem**: Story created 4 weeks ago with assumptions about app state. Now at implementation time, some assumptions are invalid.

**Solution**:
- Capture app state snapshot when story is refined (git SHA, deployed version, recent ADRs, completed stories)
- When checking if story needs refinement, include "what changed since last refinement?" context
- Dependency tracking: when story X is merged, dependent stories get flagged for re-refinement

**Result**: Stories stay valid as the app evolves.

### 3. Scalability
**Problem**: As backlog grows, manual checks become tedious. Need tooling to handle this at scale.

**Solution**:
- Single command to check entire backlog
- Single command to batch-refine all stories needing work
- Log tracks everything, making it auditable and reproducible

---

## Data Model

### Refinement Log (`refinement-log.json`)

Lives at repo root. Consumed by Claude, maintained by bash scripts.

```json
{
  "version": "1.0",
  "metadata": {
    "repo": "owner/repo-name",
    "initialized_at": "2026-03-05T10:00:00Z",
    "last_check": "2026-03-05T11:30:00Z",
    "last_batch_refinement": "2026-03-05T11:35:00Z"
  },
  "app_state": {
    "timestamp": "2026-03-05T11:30:00Z",
    "git_sha": "abc123def456",
    "deployed_version": "1.2.3",
    "completed_story_ids_recent": ["GH-100", "GH-101", "GH-102"],
    "recent_adr_files": ["ADR-005.md", "ADR-006.md"],
    "notes": "Optional: deployment notes, schema changes, etc."
  },
  "stories": {
    "GH-123": {
      "number": 123,
      "title": "User authentication overhaul",
      "url": "https://github.com/owner/repo/issues/123",
      "status": "open",
      "labels": ["needs-refinement"],
      "created_at": "2026-01-15T09:00:00Z",
      "updated_at": "2026-03-04T14:22:00Z",
      "body_hash": "sha256_of_current_issue_body",
      "refinement_status": "needs-refinement",
      "refinement_reasons": [
        {
          "type": "label",
          "value": "needs-refinement",
          "detected_at": "2026-03-04T09:15:00Z"
        }
      ],
      "last_refined": {
        "timestamp": "2026-02-28T10:00:00Z",
        "git_sha": "xyz789abc",
        "app_state_snapshot": {
          "deployed_version": "1.2.2",
          "completed_stories": ["GH-95", "GH-96"],
          "notes": "Auth service was incomplete"
        },
        "refinement_assumptions": [
          "OAuth provider API contract stable",
          "Database migrations for new schema complete",
          "Legacy auth endpoints sunset in v1.3"
        ]
      },
      "dependencies": {
        "blocks": ["GH-124", "GH-125"],
        "blocked_by": ["GH-120"],
        "relates_to": ["GH-110", "GH-111"]
      },
      "context_references": {
        "adr_files": ["ADR-002.md", "ADR-004.md"],
        "plan_files": ["planning/auth-plan.md"],
        "related_story_ids": ["GH-120", "GH-124"]
      },
      "refinement_needed_because": "Explicit 'needs-refinement' label added by team"
    },
    "GH-124": {
      "number": 124,
      "title": "Implement token refresh endpoint",
      "status": "open",
      "created_at": "2026-02-01T10:00:00Z",
      "updated_at": "2026-03-01T12:00:00Z",
      "refinement_status": "dev-ready",
      "last_refined": {
        "timestamp": "2026-03-01T12:00:00Z",
        "git_sha": "abc123def456"
      },
      "dependencies": {
        "blocked_by": ["GH-123"]
      },
      "context_references": {
        "adr_files": ["ADR-004.md"],
        "plan_files": ["planning/auth-plan.md"]
      }
    }
  }
}
```

**Key fields:**

- `refinement_status`: "dev-ready" | "needs-refinement" | "in-progress" (for future batch tracking)
- `refinement_reasons`: Array of objects explaining *why* it needs refinement (label, age, dependency, etc.)
- `last_refined`: Snapshot of app state + assumptions from last refinement
- `dependencies`: GitHub issue links (blocks, blocked_by, relates_to)
- `context_references`: Which ADRs/plan docs are relevant (populated during refinement)
- `body_hash`: Hash of issue body, used to detect if issue was edited since last refinement

---

## System Components

### 1. Bash Scripts

#### `refine-backlog.sh` (main entry point)
CLI tool with subcommands:

```bash
refine-backlog init [--repo OWNER/REPO] [--token GITHUB_TOKEN]
  # Initialize refinement-log.json in current repo
  # Create .local/bin symlink if needed

refine-backlog check [--details] [--json]
  # Determine which stories need refinement (no LLM calls)
  # Output: human-readable summary or JSON
  # Example: "3 stories need refinement: GH-123 (label), GH-125 (4+ weeks old), GH-130 (blocked-by merged)"

refine-backlog refine [--all] [--ids GH-123,GH-124] [--dry-run]
  # Refine one or more stories via Claude
  # --all: all stories with needs-refinement status
  # --ids: specific stories
  # --dry-run: show what would happen, don't update GitHub
  # Output: JSON for bash scripts to consume

refine-backlog status [--story GH-123]
  # Show current refinement status of all/specific stories

refine-backlog update-log
  # Refresh app state snapshot in log (git sha, deployed version, etc.)
```

#### `lib/fetch-stories.sh`
- Query GitHub API for all open issues
- Filter by project (if using GitHub projects feature)
- Return structured data (JSON)

#### `lib/check-needs-refinement.sh`
- Input: refinement-log.json, current backlog data
- Output: List of stories needing refinement with reasons
- Logic:
  - Stories with "needs-refinement" label → needs refinement
  - Stories open >4 weeks → needs refinement
  - Stories with blocked_by → check if blocker was recently closed → needs refinement
  - (Optional) Stories where issue body changed since last refinement → needs refinement

#### `lib/update-log.sh`
- Update refinement-log.json with:
  - New app state snapshot (git SHA, version, etc.)
  - New stories added to log
  - Refinement status updates after Claude completes work
  - Dependency tracking from GitHub issue links

#### `lib/fetch-context.sh`
- Input: story IDs, repo path
- Output: JSON with:
  - Full issue details (title, body, labels, etc.)
  - Related stories (from dependency links)
  - ADR files referenced in issue or auto-detected
  - Plan files (from convention, e.g., `planning/*-plan.md`)
  - Recent git history relevant to story

#### `lib/update-github.sh`
- Input: Refined story data (JSON from Claude)
- Actions:
  - Update GitHub issue description (if needed)
  - Remove "needs-refinement" label
  - Add "dev-ready" label
  - Add comment with refinement summary (optional)
  - Create/update dependency links

### 2. Claude Skill: `refine-backlog`

**Input**: JSON with batch of stories to refine
```json
{
  "stories": [
    {
      "number": 123,
      "title": "...",
      "current_body": "...",
      "context": {
        "adr_files": { "ADR-002.md": "file content", "ADR-004.md": "..." },
        "plan_files": { "planning/auth-plan.md": "..." },
        "related_stories": [
          { "number": 120, "title": "...", "status": "merged", "body": "..." }
        ]
      },
      "last_refinement_snapshot": {
        "deployed_version": "1.2.2",
        "assumptions": [...]
      },
      "current_app_state": {
        "deployed_version": "1.2.3",
        "completed_stories": [...],
        "recent_adrs": [...]
      }
    }
  ]
}
```

**Output**: JSON with refined stories
```json
{
  "refined_stories": [
    {
      "number": 123,
      "updated_body": "Refined issue body with updated assumptions, acceptance criteria, etc.",
      "refinement_notes": "Why this was needed, what changed, etc.",
      "dependencies_to_update": [
        {
          "type": "blocks",
          "story_number": 124,
          "reason": "This story must be completed before GH-124"
        }
      ]
    }
  ],
  "summary": "Refined 3 stories. Updated assumptions for GH-123 and GH-124. Added new dependencies."
}
```

**Claude's job**:
- Read current story + context (ADRs, plans, related stories)
- Compare last refinement snapshot to current app state
- Identify stale assumptions, missing details, outdated acceptance criteria
- Update story body to reflect current reality
- Ensure acceptance criteria are clear and testable
- Identify/update dependencies
- Output JSON for bash to consume

---

## Workflow

### Initial Setup
```bash
cd /path/to/repo
init-refine-backlog.sh --repo owner/repo-name --token $GITHUB_TOKEN

# Creates:
# - refinement-log.json (initialized with current backlog)
# - .local/bin/refine-backlog symlink
# - Updates .gitignore to exclude GitHub tokens
```

### Regular Use

**Check what needs refinement** (fast, no tokens):
```bash
refine-backlog check

# Output:
# Backlog Analysis
# ═══════════════════════════════════════
# Stories needing refinement: 5
#
# GH-123 (needs-refinement label) — User authentication overhaul
#        Created: 2026-01-15, Updated: 2026-03-04
#        Blocked by: GH-120 (merged 2026-03-02)
#
# GH-125 (open 32 days) — Dashboard redesign
#        Created: 2026-02-01, Last refined: 2026-02-15
#        Last refined under: v1.2.1, Now deployed: v1.2.3
#
# ...
```

**Refine stories** (uses Claude):
```bash
refine-backlog refine --all

# Process:
# 1. Fetch all stories needing refinement
# 2. For each, gather context (ADRs, plans, related stories)
# 3. Build single prompt to Claude with all stories
# 4. Claude returns refined bodies + notes
# 5. Update GitHub issues (remove needs-refinement, add dev-ready)
# 6. Update refinement-log.json with timestamps + snapshots
```

**Check status**:
```bash
refine-backlog status

# Output shows refinement_status for each story
```

---

## Design Principles

1. **Bash for determinism**: Fetching, filtering, and log management in bash. Fast, reproducible, auditable.

2. **Claude for inference**: Only use Claude when you need judgment (refining ambiguous requirements, detecting stale assumptions, writing clear AC).

3. **GitHub labels as source of truth**: The "needs-refinement" label is the ultimate source of truth. The log is descriptive (what happened), not prescriptive.

4. **Batch over sequential**: Refine multiple stories in one Claude call → fewer tokens, better coherence across related stories.

5. **App state snapshots**: Capture what was true when a story was refined. Later, ask "what changed?" to detect staleness.

6. **Dependency tracking**: Link stories explicitly. Use this to flag dependents for re-refinement when blockers are merged.

7. **Auditability**: Every refinement is logged (who, when, app state at that time). Easy to see why a story was refined and when.

---

## Future Extensions (not in v1, but keeping in mind)

- **Auto-trigger dependent stories**: When GH-123 merges, auto-add "needs-refinement" label to stories it blocks
- **Slack notifications**: "5 stories ready to refine" notifications
- **Refinement quality checks**: Validate that refined stories have clear AC, correct labels, etc.
- **Rollback refinement**: "I disagree with that refinement, revert to previous version"
- **Refinement history**: See all past refinements of a story, not just the latest
- **Custom triggers**: Hook into CI/CD, deployment pipelines, etc. to auto-flag stories

---

## Assumptions & Constraints

1. **GitHub as source**: Issues are in GitHub. We're not syncing from Jira, Linear, etc.

2. **ADRs follow convention**: ADR files are in a known location (e.g., `docs/adr/` or `planning/adr/`)

3. **Plan docs follow convention**: Plan files follow naming pattern (e.g., `*-plan.md` in `planning/` dir)

4. **Token limits**: Single batch refinement should fit in Claude's context (assume ~50 stories max per batch, but likely 5-15 in practice)

5. **GitHub token permissions**: Script needs `repo` scope to read/update issues

6. **Git available**: System assumes `git` is available for SHA, branch detection, etc.

---

## Error Handling & Edge Cases

- **Missing ADR/plan files**: Refinement proceeds without them, but logs that they were missing
- **GitHub API rate limit**: Script backs off gracefully, informs user
- **Stale refinement-log.json**: `refine-backlog check` refreshes automatically
- **Concurrent refinements**: Lock file prevents simultaneous refinements on same repo
- **Network issues**: Graceful fallback, don't corrupt log
