# Backlog Refinement System

A token-efficient tool for refining GitHub issues at scale using Claude. Uses bash to deterministically identify what needs refinement, then batches stories into single Claude calls for refinement.

## Quick Start

### 1. Setup

```bash
# Clone or copy the refine-backlog directory into your repo
cd your-github-repo

# Run initialization script
./refine-backlog/init-refine-backlog.sh --repo OWNER/REPO

# Edit config file to add API tokens (if not in env)
export PATH="$HOME/.local/bin:$PATH"
vim ~/.local/refine-backlog.conf
```

### 2. Check What Needs Refinement

```bash
refine-backlog check
refine-backlog check --details
refine-backlog check --json
```

### 3. Refine Stories

```bash
# Refine all stories needing work
refine-backlog refine --all

# Or refine specific stories
refine-backlog refine --ids GH-123,GH-124,GH-125

# Preview without updating
refine-backlog refine --all --dry-run

# Require confirmation before updating GitHub
refine-backlog refine --all --confirm
```

### 4. Check Status

```bash
refine-backlog status
refine-backlog status --story GH-123
refine-backlog status --json
```

## Architecture

The system has three layers:

### Layer 1: Bash Scripts (Deterministic)

Fast, reproducible analysis with no LLM calls:
- `lib/common.sh` — Foundation utilities (logging, JSON, file I/O, locking)
- `lib/github-api.sh` — GitHub REST API wrapper
- `lib/app-state.sh` — Capture current app state (git SHA, deployed version, recent changes)
- `lib/log-management.sh` — Read/write `refinement-log.json`
- `lib/backlog-analysis.sh` — Identify stories needing refinement
- `lib/context-gathering.sh` — Assemble context (ADRs, plans, related stories)

### Layer 2: CLI (refine-backlog.sh)

Main entry point with subcommands:
- `refine-backlog init` — Initialize system in repo
- `refine-backlog check` — Analyze what needs refinement
- `refine-backlog refine` — Call Claude to refine stories
- `refine-backlog status` — Show refinement status
- `refine-backlog update-log` — Capture app state snapshot

### Layer 3: Claude (Judgment)

Use Claude to:
1. Read current story + context (ADRs, plans, related stories)
2. Compare last refinement snapshot vs current app state
3. Identify stale assumptions, missing details, unclear AC
4. Return refined story bodies + notes

Two invocation methods:
- **API**: `refine-backlog refine --all` uses curl to call Anthropic API directly
- **Skill**: `/refine-backlog` in Claude Code (installed by init script)

## Key Concepts

### refinement-log.json

Tracks refinement state per story:

```json
{
  "version": "1.0",
  "metadata": {
    "repo": "OWNER/REPO",
    "initialized_at": "2026-03-05T10:00:00Z",
    "last_check": "2026-03-05T11:00:00Z",
    "last_refinement": "2026-03-05T11:30:00Z"
  },
  "app_state": {
    "timestamp": "2026-03-05T11:30:00Z",
    "git_sha": "abc123def456",
    "deployed_version": "1.2.3",
    "completed_stories": ["GH-95", "GH-100"],
    "recent_adrs": ["ADR-005.md"]
  },
  "stories": {
    "GH-123": {
      "number": 123,
      "title": "User auth overhaul",
      "refinement_status": "dev-ready",
      "refinement_reasons": [],
      "last_refined": "2026-03-05T11:30:00Z",
      "last_refined_app_state": { ... },
      "body_hash": "sha256...",
      "dependencies": {
        "blocks": [124],
        "blocked_by": [120],
        "relates_to": [119]
      }
    }
  }
}
```

### refinement_status Values

- `new` — Story in backlog, never refined
- `needs-refinement` — Story needs work (has `needs-refinement` label, is old, body changed, or blocker merged)
- `dev-ready` — Story is clear and ready for development

### Refinement Triggers

A story is flagged as `needs-refinement` if:

1. **Has label** — Tagged with `needs-refinement`
2. **Is old** — Open >28 days without refinement
3. **Body changed** — Issue body hash differs from log
4. **Blocker merged** — A `blocked_by` dependency is now closed

## Configuration

### ~/.local/refine-backlog.conf

```bash
# GitHub API token (required)
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# Anthropic API key (required for refinement)
ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxx"

# GitHub repository (auto-detected if in git repo)
GITHUB_REPO="OWNER/REPO"

# Logging level: info, debug
LOG_LEVEL="info"

# ADR file patterns (space-separated)
ADR_PATTERNS=("docs/adr/ADR-*.md" "adr/*.md")

# Plan file patterns (space-separated)
PLAN_PATTERNS=("planning/*-plan.md" "docs/planning/*-plan.md")

# Days before a story is considered "stale" for refinement
MIN_DAYS_TO_REFINEMENT="28"

# Stories per Claude API call
BATCH_SIZE="10"
```

### Environment Variables

All config values can be overridden by environment variables:

```bash
export GITHUB_TOKEN="ghp_..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GITHUB_REPO="OWNER/REPO"
export LOG_LEVEL="debug"
export BATCH_SIZE="15"

refine-backlog check
```

## Workflow Examples

### One-Time Setup

```bash
# Initialize in your repo
cd /path/to/repo
./refine-backlog/init-refine-backlog.sh --repo OWNER/REPO

# Edit config
vim ~/.local/refine-backlog.conf

# Add to PATH (optional)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

### Check What Needs Refinement

```bash
refine-backlog check
# Output:
# ℹ Analyzing backlog...
# ✓ Backlog analysis complete!
#
# Stories needing refinement: 3
# New stories: 2
# Dev-ready stories: 18
```

### Preview Refinement

```bash
refine-backlog refine --all --dry-run
# Output:
# ℹ Stories to refine: 123,124,125
# ℹ Processing 3 story(stories) in batches of 10...
# ℹ Refining batch: 123,124,125
# ℹ [DRY RUN] Would refine batch: 123,124,125
```

### Refine Stories

```bash
refine-backlog refine --all
# Output:
# ℹ Stories to refine: 123,124,125
# ℹ Processing 3 story(stories) in batches of 10...
# ℹ Refining batch: 123,124,125
# ℹ Updating GH-123...
# ✓ Refined GH-123
# ✓ Refinement complete!
```

### Check Status

```bash
refine-backlog status
# Output:
# === Refinement Status ===
# Needs refinement: 0
# Dev-ready: 21
# New: 0

refine-backlog status --story GH-123
# Output:
# Story: GH-123
# Title: User authentication overhaul
# Status: dev-ready
# Last refined: 2026-03-05T11:30:00Z
```

### Update App State

```bash
refine-backlog update-log
# Output:
# ℹ Updating app state snapshot...
# ✓ App state updated
```

## Using Claude Code Integration

The system installs a Claude skill definition that can be used in Claude Code:

```bash
# In Claude Code, you can use:
/refine-backlog

# This opens the skill with full context about refinement
```

The skill handles:
- Input validation and formatting
- Refinement logic (stale assumptions, clarity, dependencies)
- Output as JSON ready for GitHub updates

## Stale Assumption Detection

The system captures snapshots of app state when stories are refined:

```
Story GH-123 refined on Feb 28:
  deployed_version: 1.2.1
  completed_stories: [GH-95]
  recent_adrs: [ADR-003.md]

Check runs on Mar 5:
  deployed_version: 1.2.3  ← Changed!
  completed_stories: [GH-95, GH-100, GH-101]  ← More done
  recent_adrs: [ADR-003.md, ADR-005.md]  ← New ADR!

Result: GH-123 flagged as needs-refinement
Claude then detects: "Story assumed v1.2.1, now v1.2.3 deployed..."
```

## Batching & Efficiency

Stories are batched to reduce token usage:

```bash
# Single API call processes up to 10 stories
BATCH_SIZE=10

# 50 stories → 5 API calls
# 21 stories → 3 API calls
# 8 stories → 1 API call
```

Each batch call includes:
- All story bodies + context (ADRs, plans, dependencies)
- Last refinement snapshot + current app state (for stale detection)
- Claude skill definition

Total context per batch: ~20-50KB depending on file sizes.

## Troubleshooting

### "Refinement log not found"

```bash
# Initialize the log
refine-backlog init
```

### "GitHub API error"

Check:
- Token is valid and has `repo` scope
- Repository name is correct (OWNER/REPO format)
- Rate limits haven't been exceeded

```bash
# Check config
cat ~/.local/refine-backlog.conf
echo $GITHUB_TOKEN  # Should be set
```

### "Claude API error"

Check:
- Anthropic API key is valid
- Key has sufficient balance/credits
- Network connectivity

```bash
echo $ANTHROPIC_API_KEY  # Should be set
```

### "File too large" warnings

Context gathering has size limits (100KB per file) to avoid exceeding Claude's context window. Files are truncated with a warning.

### Unlock stuck refinement

If a refinement is interrupted, the lock file might remain:

```bash
# Remove lock file
rm -f ./refinement-log.json.lock

# Retry
refine-backlog refine --all
```

## Project Structure

```
refine-backlog/
├── refine-backlog.sh              # Main CLI
├── lib/
│   ├── common.sh                  # Logging, JSON, file utilities
│   ├── github-api.sh              # GitHub API wrapper
│   ├── app-state.sh               # App state capture
│   ├── log-management.sh          # Log CRUD
│   ├── backlog-analysis.sh        # Refinement detection
│   └── context-gathering.sh       # Context assembly
├── skills/
│   └── refine-backlog.md          # Claude skill definition
├── init-refine-backlog.sh         # One-time setup
└── README.md                      # This file
```

## Performance

- **Check**: 1-2 seconds (no LLM calls)
- **Refine (10 stories)**: 10-30 seconds (includes 1 API call)
- **Status**: <1 second

Token savings (vs. refining one story at a time):
- Single story: ~500 tokens (duplicate context per story)
- 10 stories in batch: ~2000 tokens (shared context once)
- **Savings: 60-75%** with batch size 10

## Contributing

To improve the system:

1. Add new functions to `lib/*.sh`
2. Update CLI in `refine-backlog.sh`
3. Document in `README.md` and skill definition
4. Test with `refine-backlog check` and `refine-backlog refine --dry-run`

## License

Use this system as you'd like. It's self-contained and designed to be forked/published.

## Support

For issues or questions:
- Check the examples above
- Review `CLAUDE.md` in the parent directory for design decisions
- Inspect `.refinement-log.json` to see current state
