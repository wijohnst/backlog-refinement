# Backlog Refinement System

A token-efficient tool for analyzing and refining GitHub issues at scale using Claude AI. Automatically detects which issues need refinement, batches them intelligently, and uses Claude to improve requirements clarity while maintaining full audit trails.

## Why Use This?

- **Uses your Claude Pro credits**: Refinement happens via `/refine-backlog` skill in Claude Code — no separate API account needed
- **Token efficient**: Batch refinement saves 60-75% on tokens vs. one-at-a-time processing
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
- Claude Code with Claude Pro or higher (for refinement via `/refine-backlog` skill)

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

# Option A: Run init script directly
/path/to/backlog-refinement/scripts/init-refine-backlog \
  --repo owner/repo \
  --token ghp_xxxxxxxxxxxx

# Option B: Use make from backlog-refinement directory
cd /path/to/backlog-refinement
make init REPO=owner/repo GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```

This will:
- Create `~/.local/refine-backlog.conf` (stores GitHub token, shared across all repos)
- Initialize `refinement-log.json` in your repo (version-controlled, only `.lock` is gitignored)
- Install the Claude skill definition to `~/.claude/commands/refine-backlog.md`

4. **GitHub Token**:

Obtain your token from:
- **GitHub Token**: https://github.com/settings/tokens → Generate new token (classic) → Check `repo` scope

Store it in `~/.local/refine-backlog.conf`:
```bash
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
GITHUB_REPO="owner/repo"
```

**Note**: Can be overridden per-command with environment variable:
```bash
# Override for a single command
GITHUB_REPO=other/repo refine-backlog check
GITHUB_TOKEN=ghp_other refine-backlog status
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

### Refine Stories (Using Claude Code Skill)

In **Claude Code**, use the `/refine-backlog` skill:

```
/refine-backlog                    # Show status and next steps
/refine-backlog --all              # Refine all stories needing work
/refine-backlog --ids GH-1,GH-2   # Refine specific stories
/refine-backlog --dry-run --all    # Preview changes without updating GitHub
```

**Refinement does:**
1. Checks which stories need refinement (bash)
2. Gathers context: ADR documents, planning docs, related stories, app state (bash)
3. Uses Claude's inference to refine stories with full context
4. Updates issue bodies with clarified acceptance criteria, assumptions, dependencies (bash)
5. Removes `needs-refinement` label (bash)
6. Logs refinement in `refinement-log.json` with snapshot of app state (bash)
7. Compares old/new app state to detect stale assumptions

**Why this design?**
- Bash for deterministic I/O (fast, auditable, no LLM calls)
- Claude for inference (uses your Claude Pro credits, batches stories efficiently)
- No separate Anthropic API account needed

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

# Target repository
GITHUB_REPO="owner/repo"

# Logging level: info, debug, error
LOG_LEVEL="info"

# Max stories per refinement call (default 10)
BATCH_SIZE="10"

# Days of inactivity to flag for refinement (default 28)
MIN_DAYS_TO_REFINEMENT="28"
```

Note: Refinement uses Claude's inference via `/refine-backlog` skill in Claude Code, which uses your Claude Pro credits. No Anthropic API key needed.

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

**Phase 1: Analysis (No LLM)**

```
Your GitHub Repo
    ↓
refine-backlog check
    ↓ (pure bash, no API calls)
refinement-log.json updated with current state
    ↓
Shows:
  - "GH-123 needs refinement (label)"
  - "GH-124 needs refinement (28 days old)"
  - "GH-125 is dev-ready"
```

**Phase 2: Refinement (Claude + Bash)**

```
/refine-backlog --all (in Claude Code)
    ↓
refine-backlog check --json (bash)
    ↓
refine-backlog gather-context --ids ... (bash)
    ↓
[Claude refines stories using context]
(uses your Claude Pro credits via chat)
    ↓
refine-backlog apply-refinement (bash)
    ↓
update_github()
    ↓ (Update issue bodies, remove label)
update_log()
    ↓ (Log refinement, capture app state)
refinement-log.json updated
```

**Design principle**: Bash for data (deterministic, auditable), Claude for judgment (inference).

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

### Example 1: Check Backlog Status

```bash
refine-backlog check

# Output:
# Stories needing refinement: 3
# New stories: 2
# Dev-ready stories: 5
```

### Example 2: Refine in Claude Code

In Claude Code session:

```
/refine-backlog --all

✓ Analyzing backlog... Found 3 stories needing refinement
✓ Gathering context... 2 ADRs, 1 plan, 2 related stories
✓ Refining with Claude... (using your chat credits)
✓ Updated GH-101: "User auth overhaul" — stale OAuth assumption fixed
✓ Updated GH-105: "Rate limiting" — clarified acceptance criteria
✓ Updated GH-110: "Caching layer" — added dependency on GH-105
✓ Refinement complete! 3 stories updated, log saved
```

### Example 3: Dry-Run Preview

In Claude Code:

```
/refine-backlog --ids GH-101,GH-105 --dry-run

✓ Would refine 2 stories:
  - GH-101: "User auth overhaul"
    Context: 2 ADRs, 1 plan, 1 related story
  - GH-105: "Rate limiting"
    Context: 1 ADR, 2 related stories

(No changes applied)

## Troubleshooting

### "GitHub API error (HTTP 401)"

Your `GITHUB_TOKEN` is missing or invalid.

**Fix**: Set `GITHUB_TOKEN` environment variable or edit `~/.local/refine-backlog.conf`:
```bash
export GITHUB_TOKEN="your_token_here"
```

### "Refinement log not found"

You haven't initialized the repo yet.

**Fix**: Run the init script in your target repository:
```bash
/path/to/backlog-refinement/scripts/init-refine-backlog --repo owner/repo --token $GITHUB_TOKEN
```

### "jq: invalid JSON text passed to --argjson"

This usually means JSON containing special characters wasn't properly escaped.

**Fix**: This has been fixed in recent versions. Update to the latest version.

### "Rate limit exceeded"

GitHub API rate limit was hit (refinement uses Claude Code, not GitHub API).

**Fix**: The system automatically waits and retries. Check your GitHub API usage:
- GitHub: https://github.com/settings/personal-access-tokens/

## Advanced Configuration

### Environment Variable Priority

All configuration values can come from environment variables (highest priority) or `~/.local/refine-backlog.conf` (fallback):

```bash
# Env vars override config file
GITHUB_TOKEN=ghp_xxx GITHUB_REPO=owner/repo refine-backlog check
```

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

### GitHub Actions (Scheduled Analysis)

```yaml
name: Analyze Backlog Daily
on:
  schedule:
    - cron: '0 9 * * MON'  # Every Monday at 9am

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up environment
        run: |
          mkdir -p ~/.local
          echo "GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}" >> ~/.local/refine-backlog.conf
      - name: Analyze backlog
        run: |
          refine-backlog check --details
      - name: Update log
        run: |
          refine-backlog update-log
      - name: Commit changes
        run: |
          git add refinement-log.json
          git commit -m "chore: update backlog analysis" || true
          git push
```

**Note**: For refinement, use `/refine-backlog` in Claude Code (not in CI/CD), since refinement requires Claude's inference.

### Pre-Sprint Planning Workflow

1. **Terminal**: Analyze backlog
```bash
refine-backlog check --details
```

2. **Claude Code**: Refine stories (preview)
```
/refine-backlog --dry-run --all
```

3. **Claude Code**: Apply refinements (if preview looks good)
```
/refine-backlog --all
```

4. **Terminal**: Commit changes
```bash
git add refinement-log.json
git commit -m "refine: update stories before sprint"
git push
```

Review refined stories in GitHub before sprint planning meeting.

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
