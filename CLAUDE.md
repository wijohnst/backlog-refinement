# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a **Backlog Refinement System** — a token-efficient tool for refining GitHub issues at scale. The system solves three key problems:

1. **Token efficiency** — Use bash to determine what needs refinement (no LLM calls), then batch multiple stories into single Claude calls
2. **Stale assumption detection** — Capture app state snapshots when refining, then detect when assumptions become invalid
3. **Scalability** — Single command to analyze and refine entire backlogs

**Key principle**: Bash for determinism (what needs refinement?), Claude only for judgment (how to refine it?).

## Architecture

### Components

1. **Bash Scripts** (`refine-backlog/`)
   - CLI tool with subcommands: `init`, `check`, `refine`, `status`, `update-log`
   - Library modules for GitHub API, backlog analysis, context gathering, log management
   - Handles all deterministic, non-inference work

2. **Claude Skill** (`refine-backlog`)
   - Receives batch of stories with full context (ADRs, plans, related stories, app state snapshots)
   - Returns refined story bodies in JSON format
   - No GitHub API calls — bash handles all updates

3. **Test Repo Setup** (`04-init-test-repo.sh`)
   - Creates clean GitHub repo with 6 sample issues
   - Pre-loads with ADRs and plan documents

### Data Model: refinement-log.json

Located at repo root. Tracks per-story refinement state:

- `version`: "1.0"
- `metadata`: repo name, initialization/check/refinement timestamps
- `app_state`: current snapshot (git SHA, deployed version, completed stories, recent ADRs)
- `stories`: keyed by "GH-{number}"
  - `refinement_status`: "dev-ready" | "needs-refinement" | "new"
  - `refinement_reasons`: array of why refinement needed (label, age, body_changed, blocker_merged)
  - `last_refined`: timestamp, git SHA, app state snapshot, refinement assumptions
  - `dependencies`: blocks, blocked_by, relates_to
  - `context_references`: which ADRs/plans were used

### Workflow

```
User: refine-backlog check
  → Bash queries GitHub (no LLM)
  → Compares against refinement-log.json
  → Output: "3 stories need refinement"

User: refine-backlog refine --all
  → Bash gathers context (ADRs, plans, related stories)
  → Calls Claude with all stories in single prompt
  → Claude returns refined bodies + notes (JSON)
  → Bash updates GitHub (bodies, labels)
  → Bash updates refinement-log.json
```

## Key Design Decisions

1. **Bash for determinism** — Fetching, filtering, log management are bash. Fast, reproducible, auditable.
2. **Claude for inference** — Only use Claude when you need judgment (unclear requirements, stale assumptions, acceptance criteria).
3. **GitHub labels as source of truth** — The `needs-refinement` label is ultimate source of truth. The log is descriptive.
4. **Batch over sequential** — Refine 5-15 stories per Claude call instead of one-at-a-time. Saves tokens, improves coherence.
5. **App state snapshots** — Capture what was true when story was refined. Later, compare to current state to detect staleness.
6. **Dependency tracking** — When GH-123 is merged, dependent stories (GH-124) can be flagged for re-refinement.
7. **Auditability** — Every refinement is logged (who, when, app state at that time). Easy to see why a story was refined.

## Common Development Tasks

### Build/Install

```bash
# One-time initialization in a repo
./refine-backlog/init-refine-backlog.sh --repo OWNER/REPO --token $GITHUB_TOKEN

# Creates:
# - refinement-log.json (initialized with current backlog)
# - .local/bin/refine-backlog symlink
# - .local/refine-backlog.conf (stores tokens)
```

### Check What Needs Refinement

```bash
# Fast analysis (no LLM calls)
refine-backlog check

# With details
refine-backlog check --details

# JSON output
refine-backlog check --json
```

### Refine Stories

```bash
# Refine all stories needing work
refine-backlog refine --all

# Refine specific stories
refine-backlog refine --ids GH-123,GH-124

# Preview without updating
refine-backlog refine --all --dry-run

# With confirmation prompt
refine-backlog refine --all --confirm
```

### Check Status

```bash
# All stories
refine-backlog status

# Specific story
refine-backlog status --story GH-123

# JSON output
refine-backlog status --json
```

### Run Tests

```bash
# Install bats test framework
npm install --save-dev bats

# Run all tests
bats test/lib/*.bats test/integration/*.bats

# Run specific module tests
bats test/lib/common.bats
bats test/integration/refine.bats

# With coverage (optional)
kcov coverage bats test/lib/*.bats
```

## Bash Script Structure

### Directory Layout

```
refine-backlog/
├── refine-backlog.sh              # Main CLI entry point
├── lib/
│   ├── common.sh                  # Logging, JSON, file utilities
│   ├── github-api.sh              # GitHub REST API wrapper
│   ├── backlog-analysis.sh        # Determine what needs refinement
│   ├── context-gathering.sh       # Fetch ADRs, plans, related stories
│   ├── log-management.sh          # Read/write refinement-log.json
│   └── app-state.sh               # Capture current app state
├── init-refine-backlog.sh         # One-time repo initialization
└── README.md                      # Usage docs
```

### Library Modules

**`lib/common.sh`** — Foundation utilities
- Logging: `log_info()`, `log_warn()`, `log_error()`, `log_debug()`
- Error handling: `fail()`, `require_command()`, `require_env()`
- JSON helpers: `json_to_var()`, `json_merge()`, `json_validate()`, `jq_filter()`
- File utilities: `ensure_file()`, `ensure_dir()`, `file_hash()`
- GitHub config: `github_token()`, `github_repo()`
- Locking: `acquire_lock()`, `release_lock()`

**`lib/github-api.sh`** — GitHub REST API wrapper
- `github_get_issues(repo, filters)` — fetch all open issues
- `github_get_issue(repo, number)` — fetch single issue
- `github_get_issue_links(repo, number)` — fetch GitHub issue links (blocks, blocked_by, relates_to)
- `github_update_issue(repo, number, updates)` — update issue body/title
- `github_add_label(repo, number, label)` / `github_remove_label(repo, number, label)`
- `github_add_comment(repo, number, body)` — add comment
- `github_get_deployed_version(repo)` — extract version from package.json/tags/VERSION file

**`lib/backlog-analysis.sh`** — Determine what needs refinement
- `analyze_backlog(repo, log_file)` → JSON array of stories needing refinement + reasons
- Logic: has `needs-refinement` label → OR → open >28 days → OR → body hash differs → OR → blocker was merged
- `reasons_for_story(story, log_entry)` → array of reason objects (type, value, detected_at, details)

**`lib/context-gathering.sh`** — Collect context for refinement
- `gather_context(repo, story_numbers)` → stories + ADRs + plans + related stories + app state
- `find_adr_files(repo_root, story_body)` — search for ADR references (explicit links + auto-detect)
- `find_plan_files(repo_root, story_keywords)` — search for plan files by convention (planning/*-plan.md)
- `read_file_safe(path, max_size)` — read files with size limits

**`lib/log-management.sh`** — Read/write refinement-log.json
- `init_log(repo, log_path)` — create new log
- `load_log(log_path)` — read and validate JSON
- `save_log(log_path, json_data)` — write atomically
- `add_story_to_log(log_path, story_number, issue_data)` — add new story
- `update_story_refinement(log_path, story_number, refinement_result)` — update after Claude refinement
- `update_app_state_in_log(log_path, app_state)` — capture current app state
- `story_by_number(log_path, number)` — look up story
- `get_needs_refinement_stories(log_path)` — filter by status

**`lib/app-state.sh`** — Capture application state
- `capture_app_state(repo_root)` → JSON with timestamp, git SHA, deployed version, recent changes
- `get_git_sha(repo_root)` — current HEAD SHA
- `get_deployed_version(repo_root)` — from git tag / package.json / VERSION file
- `get_recent_closed_stories(repo, days)` — issues closed in last N days
- `get_recent_modified_adr_files(repo_root, days)` — ADR files modified in last N days
- `get_recent_branches(repo_root, days)` — branches created/updated in last N days (optional)

### Main CLI

```bash
refine-backlog init [--repo OWNER/REPO] [--token TOKEN]
  # Initialize system in repo
  # Creates refinement-log.json, .local/bin symlink

refine-backlog check [--details] [--json] [--output FILE]
  # Analyze backlog, no LLM calls, fast
  # Shows what needs refinement and why

refine-backlog refine [--all] [--ids GH-123,GH-124] [--dry-run] [--confirm]
  # Gather context, call Claude, update GitHub + log
  # --dry-run: preview without executing
  # --confirm: skip confirmation prompt

refine-backlog status [--story GH-123] [--json]
  # Show refinement status

refine-backlog update-log
  # Refresh app state snapshot in log
```

## Claude Skill Definition

**Name**: `refine-backlog`

**Input**: JSON with batch of stories to refine
```json
{
  "stories": [
    {
      "number": 123,
      "title": "User auth overhaul",
      "current_body": "...",
      "labels": ["needs-refinement"],
      "context": {
        "adr_files": { "ADR-002.md": "contents...", "ADR-004.md": "..." },
        "plan_files": { "planning/auth-plan.md": "..." },
        "related_stories": [
          { "number": 120, "title": "...", "body": "...", "status": "merged" }
        ]
      },
      "last_refinement_snapshot": {
        "timestamp": "2026-02-28T10:00:00Z",
        "deployed_version": "1.2.2",
        "assumptions": ["OAuth provider API stable"]
      },
      "current_app_state": {
        "timestamp": "2026-03-05T11:30:00Z",
        "deployed_version": "1.2.3",
        "completed_stories": ["GH-95", "GH-100", "GH-101"],
        "recent_adrs": ["ADR-005.md"]
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
      "refinement_summary": "Updated to reflect deployed v1.2.3 and completed dependencies",
      "updated_body": "Updated issue body with refined assumptions, AC, and details",
      "key_changes": [
        "Stale assumption: assumed OAuth v1, now v2 deployed",
        "Clarified AC: specific error handling cases",
        "Added dependency: must complete before GH-124"
      ],
      "dependencies_to_update": [
        { "type": "blocks", "story_number": 124, "reason": "..." }
      ],
      "flag_for_discussion": false,
      "flag_details": ""
    }
  ],
  "refinement_notes": "High-level summary of batch. Patterns noticed?"
}
```

**Claude's Job**:
1. Read current story + context (ADRs, plans, related stories)
2. Compare last refinement snapshot to current app state
3. Identify stale assumptions, missing details, outdated AC
4. Update story body to reflect current reality
5. Ensure AC are clear and testable
6. Identify/update dependencies
7. Return JSON

**Guidelines**:
- Preserve existing issue structure unless confusing
- Be conservative with scope changes — flag for discussion rather than splitting
- Call out stale assumptions explicitly when comparing snapshots
- Keep AC testable and concrete
- Track dependencies when you notice implicit ones

## Testing

### Unit Tests (bats framework)

```bash
test/lib/
├── common.bats              # Logging, JSON, file utilities
├── github-api.bats          # GitHub API functions (mocked)
├── backlog-analysis.bats    # Detection logic
├── context-gathering.bats   # Context assembly
├── log-management.bats      # Log file operations
└── app-state.bats           # App state capture

test/integration/
├── init.bats                # Initialization workflow
├── check.bats               # Check workflow
├── refine.bats              # Refinement workflow
└── status.bats              # Status workflow

test/fixtures/               # Sample data, mocks, test repos
test/mocks/mock-github-api.sh, mock-claude.sh
```

### Manual Validation

Use test repo (created with `04-init-test-repo.sh`):
1. Initialize system
2. Run `check` — verify correct stories identified
3. Run `refine --all --dry-run` — verify what would happen
4. Run `refine --all --confirm` — verify GitHub + log updates
5. Run `check` again — verify no false positives

## Configuration

### Config File: `~/.local/refine-backlog.conf`

```bash
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxx"
LOG_LEVEL="info"  # info, debug, error
ADR_PATTERNS=("docs/adr/ADR-*.md" "adr/*.md")
PLAN_PATTERNS=("planning/*-plan.md" "docs/planning/*-plan.md")
MIN_DAYS_TO_REFINEMENT=28
BATCH_SIZE=10  # Max stories per Claude call
```

### .gitignore

```
# Refinement system
.local/refine-backlog.conf  # Don't commit tokens
refinement-log.json.lock    # Lock files
```

## Implementation Building Order

When implementing new features or fixing bugs:

1. **lib/common.sh** — Foundation (logging, JSON, file utilities)
2. **lib/github-api.sh** — GitHub interactions (can be mocked in tests)
3. **lib/app-state.sh** — App state capture
4. **lib/log-management.sh** — Log file operations
5. **lib/backlog-analysis.sh** — Detection logic
6. **lib/context-gathering.sh** — Context assembly
7. **refine-backlog.sh** — Main CLI entry point
8. **init-refine-backlog.sh** — Initialization script
9. **Claude skill** — Refinement logic
10. **Tests** — Unit, integration, manual validation

## Key Files & Locations

- **Design docs**: `/Users/wijohnst/Workspace/backlog-refinement/docs/`
  - `00-README.md` — Document overview
  - `01-DESIGN.md` — System architecture and design decisions
  - `02-IMPLEMENTATION-SPEC.md` — Detailed function specifications
  - `03-TEST-PLAN.md` — Testing strategy and scenarios
  - `IMPLEMENTATION-PROMPT.md` — Complete implementation prompt
- **Bash scripts**: `/Users/wijohnst/Workspace/backlog-refinement/refine-backlog/`
- **Tests**: `/Users/wijohnst/Workspace/backlog-refinement/test/`
- **Log file**: `refinement-log.json` (created at repo root during init)

## Important Constraints & Assumptions

1. **GitHub as source** — Issues are in GitHub. Not syncing from Jira/Linear/etc.
2. **ADRs follow convention** — ADR files in known locations (e.g., `docs/adr/` or `planning/adr/`)
3. **Plan docs follow convention** — Named as `*-plan.md` in `planning/` directory
4. **Token limits** — Single batch should fit in Claude's context (assume ~50 stories max, but 5-15 typical)
5. **Git available** — System assumes `git` command is available
6. **GitHub token permissions** — Needs `repo` scope to read/update issues

## Success Criteria for Implementation

✅ All bash functions implemented and tested
✅ GitHub API interactions correct
✅ Backlog analysis identifies right stories
✅ Claude refines stories correctly
✅ GitHub issues updated properly
✅ refinement-log.json updated correctly
✅ End-to-end workflows tested
✅ Error handling is robust
✅ Documentation is complete

## Questions to Answer While Building

- **Does the refinement log have the right fields?** Validate with real stories
- **Are "needs refinement" triggers right?** Iterate based on false positives/negatives
- **Is batch refinement efficient enough?** Try different batch sizes (5-15 stories)
- **Are Claude instructions clear?** Test with real issues and iterate
- **Error handling sufficient?** Run through failure scenarios (rate limits, API errors, network issues)

## References

- **For high-level design**: See `docs/01-DESIGN.md`
- **For function signatures**: See `docs/02-IMPLEMENTATION-SPEC.md`
- **For test scenarios**: See `docs/03-TEST-PLAN.md`
- **For test repo setup**: See `docs/IMPLEMENTATION-PROMPT.md` (includes test repo instructions)
