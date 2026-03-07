# Backlog Refinement System — Implementation Prompt

**Status**: Ready for implementation  
**Created**: 2026-03-05  
**Audience**: Engineer implementing the system

---

## Executive Summary

Build a token-efficient backlog refinement system that:

1. **Detects** which GitHub issues need refinement (using bash, no LLM calls)
2. **Batches** multiple stories into single Claude calls
3. **Updates** GitHub issues with refined bodies, labels, and dependencies
4. **Tracks** refinement history and app state snapshots in a log file

**Key insight**: Use bash for deterministic checks (what needs refinement?), Claude only for judgment (how to refine it?).

---

## What You're Building

### Three Components

1. **Bash Scripts** (`refine-backlog/`)
   - CLI tool with subcommands: `init`, `check`, `refine`, `status`, `update-log`
   - Library functions for GitHub API, backlog analysis, context gathering, log management
   - Handles all deterministic, non-inference work

2. **Claude Skill** (`refine-backlog` skill)
   - Receives batch of stories with full context (ADRs, plans, related stories)
   - Returns refined story bodies in JSON format
   - No GitHub updates from skill—bash handles that

3. **Test Repo Setup Script**
   - Creates clean GitHub repo with 6 sample issues
   - Pre-loads with ADRs and plan documents
   - Ready for end-to-end validation

---

## Architecture Overview

```
User runs: refine-backlog check
  ↓
Bash script queries GitHub (all open issues)
  ↓
Bash script compares against refinement-log.json
  ↓
Outputs: "3 stories need refinement: GH-123 (label), GH-125 (age), GH-130 (blocker merged)"
  ↓
User runs: refine-backlog refine --all
  ↓
Bash script gathers context (ADRs, plans, related stories)
  ↓
Builds JSON with all stories + context
  ↓
Claude refines all stories in single prompt
  ↓
Claude returns JSON: refined bodies, notes, dependency updates
  ↓
Bash script updates GitHub (body, labels)
  ↓
Bash script updates refinement-log.json
  ↓
Complete ✓
```

---

## Data Model

### Refinement Log (`refinement-log.json`)

Located at repo root. Tracks refinement state per story.

```json
{
  "version": "1.0",
  "metadata": {
    "repo": "owner/repo",
    "initialized_at": "2026-03-05T10:00:00Z",
    "last_check": "2026-03-05T11:30:00Z"
  },
  "app_state": {
    "timestamp": "2026-03-05T11:30:00Z",
    "git_sha": "abc123",
    "deployed_version": "1.2.3",
    "completed_story_ids_recent": ["GH-100", "GH-101"],
    "recent_adr_files": ["ADR-005.md"]
  },
  "stories": {
    "GH-123": {
      "number": 123,
      "title": "User auth overhaul",
      "url": "https://github.com/owner/repo/issues/123",
      "status": "open",
      "labels": ["needs-refinement"],
      "created_at": "2026-01-15T09:00:00Z",
      "refinement_status": "needs-refinement",
      "refinement_reasons": [
        {"type": "label", "value": "needs-refinement"}
      ],
      "last_refined": {
        "timestamp": "2026-02-28T10:00:00Z",
        "git_sha": "xyz789",
        "app_state_snapshot": {
          "deployed_version": "1.2.2",
          "completed_stories": ["GH-95"]
        },
        "refinement_assumptions": ["OAuth provider stable"]
      },
      "dependencies": {
        "blocks": ["GH-124"],
        "blocked_by": ["GH-120"],
        "relates_to": ["GH-110"]
      },
      "context_references": {
        "adr_files": ["ADR-002.md", "ADR-004.md"],
        "plan_files": ["planning/auth-plan.md"],
        "related_story_ids": ["GH-120", "GH-124"]
      }
    }
  }
}
```

---

## Bash Script Implementation

### Directory Structure

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

### Key Functions

**`lib/common.sh`**
- `log_info()`, `log_warn()`, `log_error()`, `log_debug()`
- `fail()`, `require_command()`, `require_env()`
- `json_to_var()`, `json_merge()`, `json_validate()`
- `ensure_file()`, `ensure_dir()`, `file_hash()`

**`lib/github-api.sh`**
- `github_get_issues()` — fetch all open issues
- `github_get_issue()` — fetch single issue
- `github_get_issue_links()` — fetch GitHub issue links (blocks, blocked_by, etc.)
- `github_update_issue()` — update issue body
- `github_add_label()`, `github_remove_label()` — manage labels
- `github_add_comment()` — add comment to issue
- `github_get_deployed_version()` — extract version from package.json / tags / VERSION file

**`lib/backlog-analysis.sh`**
- `analyze_backlog(repo, log_file)` — return JSON of stories needing refinement
- Logic:
  - Has `needs-refinement` label → needs refinement
  - Open >28 days → needs refinement (if not recently refined)
  - Issue body changed since last refinement → needs refinement
  - Blocked by story that was recently closed → needs refinement

**`lib/context-gathering.sh`**
- `gather_context(repo, story_ids)` — fetch full context for stories
- Returns: stories + ADR files + plan files + related stories + app state
- `find_adr_files()` — find ADRs referenced in issue or by convention
- `find_plan_files()` — find plan docs matching story keywords
- `read_file_safe()` — read files with size limits

**`lib/log-management.sh`**
- `init_log()`, `load_log()`, `save_log()`
- `add_story_to_log()` — add new story from GitHub issue
- `update_story_refinement()` — update story after refinement
- `update_app_state_in_log()` — capture current app state
- `story_by_number()`, `get_needs_refinement_stories()`

**`lib/app-state.sh`**
- `capture_app_state()` — return JSON with current git SHA, version, recent changes
- `get_git_sha()`, `get_deployed_version()`, `get_recent_closed_stories()`, `get_recent_modified_adr_files()`

### Main CLI (`refine-backlog.sh`)

Subcommands:

```bash
refine-backlog init [--repo OWNER/REPO] [--token TOKEN]
  # Initialize system in repo
  # Creates refinement-log.json, symlink to .local/bin

refine-backlog check [--details] [--json] [--output FILE]
  # Analyze backlog, show what needs refinement
  # No LLM calls, fast
  # Output: human-readable or JSON

refine-backlog refine [--all] [--ids GH-123,GH-124] [--dry-run] [--confirm]
  # Refine stories via Claude
  # Gathers context, calls Claude, updates GitHub, updates log
  # --dry-run: show what would happen
  # --confirm: skip confirmation prompt

refine-backlog status [--story GH-123] [--json]
  # Show current refinement status

refine-backlog update-log
  # Refresh app state snapshot in log
```

### Error Handling

- Validate GitHub token early
- Handle rate limiting gracefully (backoff, retry)
- Atomic file writes (temp file + move)
- Lock files to prevent concurrent refinements
- Clear error messages
- Dry-run mode to preview before executing

---

## Claude Skill Implementation

### Skill Name
`refine-backlog`

### Input Format

```json
{
  "stories": [
    {
      "number": 123,
      "title": "User auth overhaul",
      "current_body": "...",
      "labels": ["needs-refinement"],
      "created_at": "2026-01-15T09:00:00Z",
      "context": {
        "adr_files": {
          "ADR-002.md": "file contents...",
          "ADR-004.md": "..."
        },
        "plan_files": {
          "planning/auth-plan.md": "..."
        },
        "related_stories": [
          {
            "number": 120,
            "title": "...",
            "body": "...",
            "status": "merged"
          }
        ]
      },
      "last_refinement_snapshot": {
        "timestamp": "2026-02-28T10:00:00Z",
        "deployed_version": "1.2.2",
        "completed_stories": ["GH-95"],
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

### System Prompt

```
You are a backlog refinement assistant. Your job is to review GitHub issues 
and ensure they are "dev-ready" — meaning they have clear acceptance criteria, 
up-to-date assumptions, and properly scoped work.

For each story, analyze:

1. Stale Assumptions: Compare last_refinement_snapshot to current_app_state
   - Has deployed version changed? What implications?
   - Have new ADRs been added that affect this?
   - Have dependent stories been completed? Does that change scope?
   - Example: "Story assumed auth service v1, but v2 now deployed — update AC to use v2 features"

2. Unclear Acceptance Criteria:
   - Are they testable? Be concrete instead of vague
   - Are there missing edge cases?
   - Do they align with related stories?

3. Scope & Dependencies:
   - Is this story good size for one sprint?
   - Does it clearly state what depends on it / what it depends on?
   - Are implicit dependencies captured?

4. Technical Clarity:
   - Does it reference relevant ADRs?
   - Are architectural decisions clear?
   - Any implementation concerns mentioned?

Return JSON (see format below). Be concise but thorough. Focus on making 
the story clear and actionable for developers.
```

### Output Format

```json
{
  "refined_stories": [
    {
      "number": 123,
      "refinement_summary": "Brief explanation of what was refined and why",
      "updated_body": "Complete updated issue body. Keep existing structure but update assumptions, AC, and details.",
      "key_changes": [
        "Stale assumption found: story assumed auth v1, now v2 deployed",
        "Clarified AC #2: from 'handle errors' to '401/403 errors with specific user messaging'",
        "Added dependency note: must complete before GH-124"
      ],
      "dependencies_to_update": [
        {
          "type": "blocks",
          "story_number": 124,
          "reason": "This story must complete before GH-124 work begins"
        }
      ],
      "flag_for_discussion": false,
      "flag_details": ""
    }
  ],
  "refinement_notes": "High-level summary. Any patterns across stories?"
}
```

### Guidelines

- **Preserve structure** unless confusing. Refine ≠ rewrite
- **Be conservative** on scope changes. Flag for discussion rather than splitting
- **Call out stale assumptions explicitly** when comparing snapshots
- **Keep AC testable** and concrete
- **Track dependencies** when you notice implicit ones

---

## Integration Flow

### How Bash Calls Claude

In `cmd_refine()`:

```bash
# 1. Gather context
context_json=$(gather_context "$repo" "$story_ids")

# 2. Call Claude (via API)
refinement_result=$(call_claude_api "$system_prompt" "$context_json")

# 3. Parse JSON response
refined_stories=$(echo "$refinement_result" | jq '.refined_stories[]')

# 4. For each refined story:
for story in $refined_stories; do
  number=$(echo "$story" | jq '.number')
  updated_body=$(echo "$story" | jq '.updated_body')
  
  # Update GitHub
  github_update_issue "$repo" "$number" "{\"body\": \"$updated_body\"}"
  github_remove_label "$repo" "$number" "needs-refinement"
  github_add_label "$repo" "$number" "dev-ready"
  
  # Update log
  update_story_refinement "$log_file" "$number" "$story"
done
```

### Calling Claude

Choose one approach:

**Option A: Direct API Call**
```bash
call_claude_api(system_prompt, user_prompt) {
  curl -s -X POST https://api.anthropic.com/v1/messages \
    -H "Authorization: token ${ANTHROPIC_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"claude-opus-4-5\",
      \"max_tokens\": 4000,
      \"system\": \"$system_prompt\",
      \"messages\": [{\"role\": \"user\", \"content\": \"$user_prompt\"}]
    }" | jq '.content[0].text'
}
```

**Option B: Claude CLI Wrapper**
```bash
call_claude_api(system_prompt, user_prompt) {
  echo "$system_prompt" > /tmp/sys.txt
  echo "$user_prompt" > /tmp/user.txt
  claude --system /tmp/sys.txt /tmp/user.txt
}
```

---

## Testing Strategy

### Unit Tests (using bats)

```bash
# Install bats
npm install --save-dev bats

# Create test files
test/lib/common.bats          # Test logging, JSON, file utilities
test/lib/github-api.bats      # Test GitHub API functions
test/lib/backlog-analysis.bats # Test detection logic
test/lib/context-gathering.bats
test/lib/log-management.bats
test/lib/app-state.bats

test/integration/init.bats    # Test init workflow
test/integration/check.bats   # Test check workflow
test/integration/refine.bats  # Test refine workflow
test/integration/status.bats  # Test status workflow

# Run tests
bats test/**/*.bats
```

### Integration Tests

- Mock GitHub API and Claude
- Test full workflows (init → check → refine → status)
- Test error scenarios
- Test idempotency

### Manual Validation

Use the provided `init-test-repo.sh` script:

```bash
# Create test repo with sample issues
./04-init-test-repo.sh --repo YOUR_ACCOUNT/test-repo --token $GITHUB_TOKEN

# Initialize system
cd /tmp/refine-backlog-test-*
refine-backlog init --repo YOUR_ACCOUNT/test-repo --token $GITHUB_TOKEN

# Check backlog
refine-backlog check --details
# Should show: 3 stories need refinement

# Refine stories (dry-run first)
refine-backlog refine --all --dry-run
refine-backlog refine --all --confirm
# Should update GitHub + log

# Check again
refine-backlog check
# Should show: 0 stories need refinement
```

---

## Configuration & Installation

### Config File

`~/.local/refine-backlog.conf`:
```bash
GITHUB_TOKEN="ghp_xxxx"
ANTHROPIC_API_KEY="sk-ant-xxxx"
LOG_LEVEL="info"
ADR_PATTERNS=("docs/adr/ADR-*.md")
PLAN_PATTERNS=("planning/*-plan.md")
```

### Installation

```bash
# One-time initialization
./init-refine-backlog.sh --repo OWNER/REPO --token $GITHUB_TOKEN

# Creates:
# - refinement-log.json
# - .local/bin/refine-backlog symlink
# - .local/refine-backlog.conf
```

### Usage

```bash
# Anywhere in repo or subdirectories
refine-backlog check
refine-backlog refine --all
refine-backlog status
```

---

## Success Criteria

✅ All bash functions work and are tested  
✅ GitHub API interactions are correct  
✅ Backlog analysis identifies right stories  
✅ Claude refines stories correctly  
✅ GitHub issues updated properly  
✅ refinement-log.json updated correctly  
✅ End-to-end workflows tested  
✅ Error handling is robust  
✅ Documentation is complete  

---

## Building Order

1. **lib/common.sh** — Foundation (logging, JSON, file utilities)
2. **lib/github-api.sh** — GitHub interactions (mocked in tests)
3. **lib/app-state.sh** — App state capture
4. **lib/log-management.sh** — Log file operations
5. **lib/backlog-analysis.sh** — Detection logic
6. **lib/context-gathering.sh** — Context assembly
7. **refine-backlog.sh** — Main CLI
8. **init-refine-backlog.sh** — Initialization script
9. **Claude skill** — Refinement logic
10. **Tests** — Unit, integration, manual

---

## Additional Resources

- Design document: See `01-DESIGN.md` for architecture and design decisions
- Detailed spec: See `02-IMPLEMENTATION-SPEC.md` for complete function signatures
- Test plan: See `03-TEST-PLAN.md` for test scenarios and validation
- Test repo script: See `04-init-test-repo.sh` to set up testing environment

---

## Questions to Answer As You Build

- **Does the refinement log have the right fields?** Test with real stories to refine the structure
- **Are "needs refinement" triggers right?** Iterate based on false positives/negatives
- **Is batch refinement efficient?** Try different batch sizes
- **Are Claude instructions clear?** Test with real issues and iterate
- **Error handling sufficient?** Run through failure scenarios

---

## Notes

- **Move inference to deterministic layer**: Bash for detection, Claude only for judgment
- **Preserve GitHub as source of truth**: Labels are user-facing, log is system-facing
- **Make everything auditable**: Every action logged, easy to see why refinement happened
- **Design for iteration**: Start simple, add features as you learn
- **Test thoroughly**: Unit + integration + manual validation

Ready to build. Start with the foundation (common.sh), then layer up. Good luck!

