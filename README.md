# Backlog Refinement System

A token-efficient tool for analyzing and refining GitHub issues at scale using Claude AI. Automatically detects which issues need refinement, batches them intelligently, and uses Claude to improve requirements clarity while maintaining full audit trails.

## Why Use This?

- **Token efficient**: Batch refinement saves 60-75% on API costs vs. one-at-a-time processing
- **Automated detection**: Identify stale, unclear, or dependency-blocked issues without manual review
- **Audit trail**: Every refinement is logged with timestamps, git state, and assumptions captured
- **Deterministic**: Uses bash for all logic that doesn't require judgment, avoiding unnecessary LLM calls
- **Self-contained**: Single command to analyze and refine your entire backlog

## Quick Start

### Prerequisites

- Bash 4.0+
- `jq` (JSON processor)
- `git` with GitHub remote configured
- GitHub token with `repo` scope
- Anthropic API key (for refinement features)

### Installation

1. **Clone the repository**:
```bash
git clone https://github.com/wijohnst/backlog-refinement.git
cd backlog-refinement
```

2. **Install the CLI** (one-time):
```bash
# Option A: Using Make
make install

# Option B: Manual
ln -s "$(pwd)/bin/refine-backlog" ~/.local/bin/refine-backlog
export PATH="$HOME/.local/bin:$PATH"  # Add to .zshrc or .bashrc to persist
```

3. **Initialize in your target repository**:
```bash
cd /path/to/your/github/repo
/path/to/backlog-refinement/scripts/init-refine-backlog
```

This will:
- Create `~/.local/refine-backlog.conf` (stores API tokens)
- Initialize `refinement-log.json` in your repo
- Install the Claude skill definition

4. **Configure API tokens**:

Edit `~/.local/refine-backlog.conf`:
```bash
GITHUB_TOKEN="your_github_token_here"
ANTHROPIC_API_KEY="your_anthropic_api_key_here"
GITHUB_REPO="owner/repo"
```

5. **Verify setup**:
```bash
refine-backlog check
```

You should see a summary of stories needing refinement (or "No stories to refine" if your backlog is ready).

## Usage

### Analyze Your Backlog (No LLM Calls)

```bash
# Quick overview
refine-backlog check

# With detailed reasons
refine-backlog check --details

# JSON output for scripting
refine-backlog check --json > backlog.json
```

**Output shows:**
- Stories with `needs-refinement` label
- Stories open >28 days without refinement
- Stories whose body text has changed since last refinement
- Stories blocked by dependencies that have been merged

### Refine Stories

```bash
# Refine all stories needing work
refine-backlog refine --all

# Refine specific stories
refine-backlog refine --ids GH-123,GH-124,GH-125

# Preview changes without updating
refine-backlog refine --all --dry-run

# Interactive confirmation
refine-backlog refine --all --confirm
```

**Refinement does:**
1. Gathers context: ADR documents, planning docs, related stories, app state
2. Calls Claude with full context (5-15 stories per call)
3. Updates issue bodies with clarified acceptance criteria, assumptions, dependencies
4. Removes `needs-refinement` label
5. Logs refinement in `refinement-log.json` with snapshot of app state
6. Compares old/new app state to detect stale assumptions

### Check Status

```bash
# All stories
refine-backlog status

# Specific story
refine-backlog status --story GH-123

# JSON output
refine-backlog status --json
```

### Update App State Snapshot

```bash
# Refresh git SHA, deployed version, recent activity
refine-backlog update-log
```

Run this periodically or after deployments to keep the system's view of your app state current.

## Configuration

### Config File: `~/.local/refine-backlog.conf`

Created during `init-refine-backlog.sh`. Edit to customize:

```bash
# GitHub token for API access
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# Anthropic API key for Claude
ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxx"

# Target repository
GITHUB_REPO="owner/repo"

# Logging level: info, debug, error
LOG_LEVEL="info"

# Max stories per Claude call (default 10)
BATCH_SIZE="10"

# Days of inactivity to flag for refinement (default 28)
MIN_DAYS_TO_REFINEMENT="28"
```

### Using Labels

The system recognizes two special labels:

- **`needs-refinement`**: Marks a story as needing clarification. The system will automatically detect and refine these.
- **Detected automatically**: Stories missing in the refinement log, or with changed bodies, or blocked by merged dependencies.

## Project Structure

```
backlog-refinement/
├── bin/
│   └── refine-backlog           # Main CLI entry point
├── lib/
│   ├── common.sh                # Logging, utilities, config
│   ├── github-api.sh            # GitHub API wrapper
│   ├── app-state.sh             # Git state & version detection
│   ├── log-management.sh        # refinement-log.json CRUD
│   ├── backlog-analysis.sh      # Identify stories needing refinement
│   └── context-gathering.sh     # Find ADRs, plans, related stories
├── scripts/
│   └── init-refine-backlog      # One-time setup for a repo
├── skills/
│   └── refine-backlog.md        # Claude skill definition
├── test/                         # Unit & integration tests
├── docs/                         # Architecture & design docs
├── Makefile                      # Install/test/clean targets
├── README.md                     # This file
├── CLAUDE.md                     # Project guidelines
└── package.json                  # Test runner (bats)
```

## How It Works

### Architecture

```
Your GitHub Repo
    ↓
refine-backlog check
    ↓ (No LLM calls - pure bash analysis)
refinement-log.json
    ↓
↓→ "GH-123 needs refinement (label)"
↓→ "GH-124 needs refinement (28 days old)"
↓→ "GH-125 is dev-ready"
```

Then:

```
refine-backlog refine --all
    ↓
gather_context()
    ↓ (Find ADRs, plans, related stories)
call_claude_api()
    ↓ (Batch: 5-15 stories per call)
Claude returns refined bodies + notes
    ↓
update_github()
    ↓ (Update issue bodies, remove label)
update_log()
    ↓ (Log refinement, capture app state)
refinement-log.json updated
```

### The Refinement Log

Located at repo root: `refinement-log.json`

Tracks per-story state:

```json
{
  "version": "1.0",
  "metadata": {
    "repo": "owner/repo",
    "initialized_at": "2026-03-07T10:00:00Z",
    "last_check": "2026-03-07T11:30:00Z",
    "last_refinement": "2026-03-07T12:00:00Z"
  },
  "app_state": {
    "timestamp": "2026-03-07T12:00:00Z",
    "git_sha": "abc1234",
    "deployed_version": "1.2.3",
    "completed_stories": ["GH-95", "GH-100"]
  },
  "stories": {
    "GH-123": {
      "number": 123,
      "title": "User authentication",
      "refinement_status": "dev-ready",
      "last_refined": "2026-03-07T12:00:00Z",
      "body_hash": "sha256...",
      "dependencies": {
        "blocks": [],
        "blocked_by": [120],
        "relates_to": [119]
      }
    }
  }
}
```

## Context Detection

The system automatically discovers and includes context for refinement:

### Architectural Decision Records (ADRs)

Looks for:
- `docs/adr/ADR-*.md`
- `adr/ADR-*.md`
- Explicit references in story body: "ADR-002" or "adr-002"

### Planning Documents

Looks for:
- `planning/*-plan.md`
- `docs/planning/*-plan.md`
- Files matching story keywords

### Related Stories

Includes stories linked by:
- `blocks`, `closes`, `fixes` relationships
- `blocked by`, `depends on` relationships
- `relates to`, `related to` relationships

## Refinement Quality

Claude refines stories by:

1. **Clarifying assumptions**: Comparing app state snapshots to detect what changed
2. **Clarifying acceptance criteria**: Making testable, specific, measurable
3. **Adding context**: Including relevant ADRs, dependencies, design rationale
4. **Updating dependencies**: Identifying implicit relationships
5. **Flagging ambiguity**: Marking stories that need discussion before dev starts

## Examples

### Example 1: Refine a Single Story

```bash
refine-backlog refine --ids GH-42

# Output:
# ℹ Refining 1 story...
# ℹ Gathering context for GH-42...
# ℹ Context gathered: 2 ADRs, 1 plan, 2 related stories
# ℹ Calling Claude API...
# ℹ Updated GH-42: "Better error messages for auth failures"
# ✓ Refinement complete
```

### Example 2: Dry-Run Before Refining All

```bash
refine-backlog refine --all --dry-run

# Output:
# ℹ Analyzing backlog...
# ℹ 3 stories need refinement (dry-run mode)
#   • GH-101: User auth overhaul (28 days old)
#   • GH-105: Rate limiting (has needs-refinement label)
#   • GH-110: Caching layer (body changed)
#
# Would refine 3 stories in 1 batch
# Would call Claude API 1 time
# Estimated tokens: ~15,000
```

### Example 3: Interactive Refinement

```bash
refine-backlog refine --all --confirm

# Prompts:
# ℹ 3 stories need refinement
# Continue? (y/n) y
# ℹ Refining batch 1/1 (3 stories)...
# ✓ Refinement complete
```

## Troubleshooting

### "GitHub API error (HTTP 401)"

Your `GITHUB_TOKEN` is missing or invalid.

**Fix**: Set `GITHUB_TOKEN` environment variable or edit `~/.local/refine-backlog.conf`:
```bash
export GITHUB_TOKEN="your_token_here"
```

### "Refinement log not found"

You haven't initialized the repo yet.

**Fix**: Run `refine-backlog init` in your target repository.

### "jq: invalid JSON text passed to --argjson"

This usually means JSON containing special characters wasn't properly escaped.

**Fix**: This has been fixed in recent versions. Update to the latest version.

### "Rate limit exceeded"

GitHub or Anthropic API rate limits were hit.

**Fix**: The system automatically waits and retries. Check your API usage:
- GitHub: https://github.com/settings/personal-access-tokens/
- Anthropic: https://console.anthropic.com/

## Advanced Configuration

### Custom Batch Size

Process fewer stories per Claude call (for lower cost per call):

```bash
BATCH_SIZE=5 refine-backlog refine --all
```

### Debug Logging

See detailed logs:

```bash
LOG_LEVEL=debug refine-backlog check
```

### Custom Paths

Point to a different repo or log file:

```bash
GITHUB_REPO="other/repo" refine-backlog check
LOG_FILE="/path/to/custom-log.json" refine-backlog check
```

## Integration Examples

### GitHub Actions (Scheduled Refinement)

```yaml
name: Refine Backlog Daily
on:
  schedule:
    - cron: '0 9 * * MON'  # Every Monday at 9am

jobs:
  refine:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up environment
        run: |
          mkdir -p ~/.local
          echo "GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}" >> ~/.local/refine-backlog.conf
          echo "ANTHROPIC_API_KEY=${{ secrets.ANTHROPIC_API_KEY }}" >> ~/.local/refine-backlog.conf
      - name: Analyze backlog
        run: |
          refine-backlog check --details
```

### Pre-Sprint Planning

```bash
#!/bin/bash
# Refine backlog before sprint planning meeting

refine-backlog check --json > backlog-status.json
refine-backlog refine --all --dry-run > refinement-preview.txt

echo "Backlog status saved to backlog-status.json"
echo "Refinement preview saved to refinement-preview.txt"
echo "Review and commit before sprint planning"
```

### CI/CD Pipeline

```bash
# In your pre-deployment hook:
refine-backlog update-log

# Captures current deployed version and git state
# Next refinement run will compare against this
```

## Contributing

Contributions welcome! Areas where help is needed:

- Additional context detection (Jira, Linear, other tools)
- Better Claude prompts for specific domain refinements
- Integration tests with real GitHub repos
- Performance improvements for large backlogs

## License

MIT - See LICENSE file

## Support

- **Issues**: Report bugs on GitHub: https://github.com/wijohnst/backlog-refinement/issues
- **Discussions**: Ask questions: https://github.com/wijohnst/backlog-refinement/discussions
- **Documentation**: See `/docs` directory for detailed design docs

## Acknowledgments

Built with:
- Claude AI (Anthropic)
- GitHub API
- jq
- Bash

## Roadmap

- [ ] Support for multiple LLM providers (OpenAI, local models)
- [ ] Better dependency visualization
- [ ] Historical refinement analytics
- [ ] Team collaboration features (comments, reviews)
- [ ] Jira/Linear integration
- [ ] Web dashboard
