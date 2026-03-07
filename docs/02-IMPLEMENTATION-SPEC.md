# Backlog Refinement System — Implementation Specification

## Overview

Build a token-efficient backlog refinement system consisting of:
1. **Bash scripts** for deterministic backlog management, analysis, and GitHub API interactions
2. **Claude skill** for intelligent story refinement
3. **Initialization script** to bootstrap the system in a new repo

---

## Part 1: Bash Scripts

### Directory Structure

```
refine-backlog/
├── refine-backlog.sh          # Main entry point (CLI)
├── lib/
│   ├── common.sh              # Shared utilities (logging, error handling, JSON helpers)
│   ├── github-api.sh          # GitHub API calls (fetch issues, update, etc.)
│   ├── backlog-analysis.sh    # Check what needs refinement, why
│   ├── context-gathering.sh   # Fetch ADRs, plans, related stories
│   ├── log-management.sh      # Read/write refinement-log.json
│   └── app-state.sh           # Capture current app state (git SHA, version, etc.)
├── init-refine-backlog.sh     # Initialization script
└── README.md                  # Usage instructions
```

### Common Functions (`lib/common.sh`)

Provide utilities used by other scripts:

```bash
# Logging
log_info(message)      # Green [INFO]
log_warn(message)      # Yellow [WARN]
log_error(message)     # Red [ERROR]
log_debug(message)     # Gray [DEBUG], only if DEBUG=1

# Error handling
fail(message)          # Log error and exit 1
require_command(cmd)   # Exit if command not available
require_env(VAR)       # Exit if env var not set

# GitHub config
github_token()         # Get GITHUB_TOKEN from env or .local/refine-backlog.conf
github_repo()          # Get OWNER/REPO from config or current git remote

# JSON helpers
json_to_var(file, path)        # Extract value from JSON file using jq
json_merge(file1, file2)       # Merge two JSON objects
json_validate(file)            # Validate JSON syntax
jq_filter(expression, input)   # Safe jq wrapper

# File utilities
ensure_file(path)              # Create if doesn't exist
ensure_dir(path)               # Create directory if doesn't exist
file_hash(path)                # SHA256 hash of file (for body_hash tracking)

# Locking
acquire_lock(name)             # Create lock file, wait if locked
release_lock(name)             # Remove lock file
```

### GitHub API (`lib/github-api.sh`)

Wrapper around GitHub REST API:

```bash
github_get_issues(repo, filters)
  # Fetch all open issues from repo
  # filters: optional jq filter (e.g., 'label:needs-refinement')
  # Output: JSON array of issues
  # Fields: number, title, body, labels, created_at, updated_at, state, etc.

github_get_issue(repo, number)
  # Fetch single issue by number
  # Output: full issue object

github_get_issue_links(repo, number)
  # Fetch GitHub issue links (blocks, blocked_by, relates_to)
  # Note: These are in "issue relationships" via API
  # Output: JSON with depends_on, blocks, relates_to arrays

github_update_issue(repo, number, updates)
  # Update issue fields
  # updates: JSON object with keys: title, body, labels
  # Returns: updated issue object

github_add_label(repo, number, label)
  # Add label to issue

github_remove_label(repo, number, label)
  # Remove label from issue

github_add_comment(repo, number, body)
  # Add comment to issue

github_get_deployed_version(repo)
  # Try to extract version from:
  # - Most recent release/tag
  # - package.json version field
  # - VERSION file in repo root
  # Returns: version string or "unknown"
```

### Backlog Analysis (`lib/backlog-analysis.sh`)

Determine which stories need refinement:

```bash
analyze_backlog(repo, log_file)
  # Input: 
  #   repo: OWNER/REPO
  #   log_file: path to refinement-log.json
  #
  # Output: JSON array of stories needing refinement, with reasons
  # {
  #   "needs_refinement": [
  #     {
  #       "number": 123,
  #       "reasons": [
  #         {"type": "label", "value": "needs-refinement"},
  #         {"type": "age", "days": 35}
  #       ]
  #     }
  #   ],
  #   "already_refined": [...]
  # }
  #
  # Logic:
  # 1. Fetch current open issues from GitHub
  # 2. For each issue in log:
  #    - Has "needs-refinement" label? → needs refinement
  #    - Created >28 days ago AND last_refined >28 days ago? → needs refinement
  #    - Issue body_hash differs from logged body_hash? → needs refinement
  #    - blocked_by link points to merged issue? → needs refinement
  # 3. For new issues not in log:
  #    - Add to log with status "new", no refinement status yet

reasons_for_story(story, log_entry)
  # Input: current issue, log entry
  # Output: array of reason objects
  # Each reason: {type, value, [detected_at, details]}
  # Types: "label", "age", "body_changed", "blocker_merged", "new"
```

### Context Gathering (`lib/context-gathering.sh`)

Collect files and context needed for refinement:

```bash
gather_context(repo, story_numbers)
  # Input: repo, array of story IDs
  # Output: JSON with:
  # {
  #   "stories": [
  #     {
  #       "number": 123,
  #       "body": "full issue body",
  #       "labels": [...],
  #       "context": {
  #         "adr_files": {"ADR-001.md": "file contents", ...},
  #         "plan_files": {"planning/auth-plan.md": "file contents", ...},
  #         "related_stories": [
  #           {"number": 120, "title": "...", "body": "...", "status": "merged"}
  #         ]
  #       },
  #       "last_refinement_snapshot": {...},  # from log
  #       "current_app_state": {...}          # from app-state.sh
  #     }
  #   ]
  # }
  #
  # Process:
  # 1. Fetch each issue from GitHub
  # 2. Extract ADR references from issue body (e.g., [ADR-001](docs/adr/ADR-001.md))
  # 3. Search for plan files matching story (auth story → planning/auth-plan.md)
  # 4. Fetch related/blocked stories from GitHub links
  # 5. Read file contents from disk
  # 6. Add app state snapshot from log
  # 7. Get current app state from app-state.sh

find_adr_files(repo_root, story_body)
  # Search for ADR references in story body
  # Patterns:
  #   - Explicit links: [ADR-001](docs/adr/ADR-001.md)
  #   - Text references: "See ADR-001"
  #   - Auto-detect: search docs/ for ADR-*.md files
  # Output: array of file paths

find_plan_files(repo_root, story_keywords)
  # Search for plan files matching story keywords
  # Convention: planning/*-plan.md
  # Example: "auth" story → planning/auth-plan.md, planning/security-plan.md
  # Output: array of file paths

read_file_safe(path, max_size)
  # Read file with safeguards
  # max_size: prevent loading huge files (default 100KB)
  # Returns: file contents or error message
```

### Log Management (`lib/log-management.sh`)

Read and update refinement-log.json:

```bash
init_log(repo, log_path)
  # Create new refinement-log.json
  # Input: repo (OWNER/REPO)
  # Initialize:
  # - version: "1.0"
  # - metadata: timestamps, repo name
  # - app_state: current snapshot (via app-state.sh)
  # - stories: empty dict, will be populated

load_log(log_path)
  # Read refinement-log.json, validate JSON
  # Output to stdout, or fail with error message

save_log(log_path, json_data)
  # Write JSON to refinement-log.json atomically
  # Use temp file + mv to prevent corruption

add_story_to_log(log_path, story_number, issue_data)
  # Add new story to log
  # Populate from GitHub issue data
  # Initial status: "new" (not yet refined or needs-refinement)

update_story_refinement(log_path, story_number, refinement_result)
  # After Claude refines a story:
  # - Set refinement_status to "dev-ready"
  # - Set last_refined timestamp + git SHA + app state
  # - Update dependencies (from refinement_result)
  # - Update context_references (which ADRs/plans were used)
  # - Compute new body_hash

update_app_state_in_log(log_path, app_state)
  # Update the app_state section of log with fresh snapshot
  # (called before each refinement to capture current state)

story_by_number(log_path, number)
  # Look up single story in log
  # Output: story object or null

get_needs_refinement_stories(log_path)
  # Filter stories with refinement_status == "needs-refinement"
  # Output: array of story objects
```

### App State (`lib/app-state.sh`)

Capture current application state:

```bash
capture_app_state(repo_root)
  # Output: JSON with current app state
  # {
  #   "timestamp": "ISO timestamp of capture",
  #   "git_sha": "current HEAD SHA",
  #   "deployed_version": "version from package.json / release / VERSION file",
  #   "completed_story_ids_recent": ["GH-100", "GH-101"], // closed in last 7 days
  #   "recent_adr_files": ["ADR-005.md", "ADR-006.md"],   // modified in last 7 days
  #   "branch": "main",
  #   "remote_url": "github.com/owner/repo"
  # }

get_git_sha(repo_root)
  # Return current HEAD SHA (short form)

get_deployed_version(repo_root)
  # Try sources in order:
  # 1. Most recent git tag matching vX.Y.Z pattern
  # 2. version field in package.json
  # 3. VERSION file in repo root
  # 4. Return "unknown" if none found

get_recent_closed_stories(repo, days)
  # Fetch issues closed in last N days
  # Return array of issue numbers
  # Use GitHub API (closed:>2026-02-26)

get_recent_modified_adr_files(repo_root, days)
  # Find ADR files modified in last N days
  # Convention: docs/adr/ADR-*.md or similar
  # Return array of file paths

get_recent_branches(repo_root, days)
  # Get list of branches created/updated in last N days
  # (optional, for context about ongoing work)
```

### Main CLI (`refine-backlog.sh`)

Entry point with subcommands:

```bash
#!/bin/bash
# refine-backlog.sh — Main entry point

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

main() {
  local command="${1:-}"
  
  case "$command" in
    init)
      cmd_init "$@"
      ;;
    check)
      cmd_check "$@"
      ;;
    refine)
      cmd_refine "$@"
      ;;
    status)
      cmd_status "$@"
      ;;
    update-log)
      cmd_update_log "$@"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

cmd_init() {
  # Initialize refinement system in current repo
  # Usage: refine-backlog init [--repo OWNER/REPO] [--token TOKEN]
  #
  # Steps:
  # 1. Validate git repo
  # 2. Prompt for GitHub repo (OWNER/REPO) if not provided
  # 3. Validate token access
  # 4. Fetch current backlog from GitHub
  # 5. Create refinement-log.json
  # 6. Symlink to .local/bin if needed
  # 7. Add refinement-log.json to .gitignore
  # 8. Print success message with next steps
}

cmd_check() {
  # Analyze backlog, show what needs refinement
  # Usage: refine-backlog check [--details] [--json] [--output FILE]
  #
  # Flags:
  # --details: show detailed reasons for each story
  # --json: output JSON instead of human-readable
  # --output: write to file instead of stdout
  #
  # Process:
  # 1. Load refinement-log.json
  # 2. Call analyze_backlog()
  # 3. Format output
  # 4. Print summary + list of stories needing refinement
  #
  # Example output:
  # Backlog Analysis
  # ═══════════════════════════════════════
  # Stories needing refinement: 3
  # 
  # GH-123 (needs-refinement label) — User auth overhaul
  #        Last refined: 2026-02-28 (5 days ago)
  #        Deployed version changed: 1.2.2 → 1.2.3
  # 
  # GH-125 (open 32 days) — Dashboard redesign
  # ...
}

cmd_refine() {
  # Refine one or more stories via Claude
  # Usage: refine-backlog refine [--all] [--ids GH-123,GH-124] [--dry-run]
  #
  # Flags:
  # --all: refine all stories with needs-refinement status
  # --ids: specific story numbers (comma-separated)
  # --dry-run: show what would happen, don't update GitHub
  # --confirm: skip confirmation prompt
  #
  # Process:
  # 1. Determine which stories to refine (--all or --ids)
  # 2. Gather context for each story
  # 3. Build prompt + context for Claude
  # 4. Call Claude skill (see Part 2)
  # 5. Parse refinement results (JSON)
  # 6. Update GitHub issues (remove needs-refinement, add dev-ready)
  # 7. Update refinement-log.json
  # 8. Print summary (X stories refined, Y GitHub updates made)
  #
  # Error handling:
  # - If Claude returns error, roll back any GitHub updates
  # - If GitHub API rate limit hit, pause and retry
}

cmd_status() {
  # Show current refinement status
  # Usage: refine-backlog status [--story GH-123] [--json]
  #
  # Output:
  # Story refinement status:
  # ═════════════════════════════════════════
  # GH-123: dev-ready (last refined 2026-03-05)
  # GH-124: dev-ready (last refined 2026-03-01)
  # GH-125: needs-refinement (needs-refinement label)
  # GH-126: new (not yet refined)
  # ...
}

cmd_update_log() {
  # Refresh app state snapshot in log
  # Usage: refine-backlog update-log
  #
  # Process:
  # 1. Capture current app state (git SHA, version, etc.)
  # 2. Check for recently closed stories
  # 3. Check for recently modified ADRs
  # 4. Update app_state section in refinement-log.json
  # 5. (Optional) Check if any stories' assumptions are stale
  #
  # Used before batch refinement to ensure current app state is captured
}

usage() {
  cat <<EOF
Usage: refine-backlog <command> [options]

Commands:
  init                Initialize refinement system in current repo
  check               Analyze backlog, show what needs refinement
  refine              Refine one or more stories via Claude
  status              Show current refinement status
  update-log          Refresh app state snapshot in log

For detailed help: refine-backlog <command> --help
EOF
}

main "$@"
```

### Initialization Script (`init-refine-backlog.sh`)

Standalone script to bootstrap the system:

```bash
#!/bin/bash
# init-refine-backlog.sh
# One-time setup script to install refine-backlog system

set -euo pipefail

# Steps:
# 1. Detect if running in a git repo
# 2. Prompt for/validate GitHub repo (OWNER/REPO)
# 3. Prompt for/validate GitHub token
# 4. Determine installation location
#    - If --scripts-dir provided, use that
#    - Otherwise, look for ./scripts/ in repo
#    - Otherwise, use ~/.local/bin/refine-backlog/
# 5. Copy refine-backlog/ directory to installation location
# 6. Make scripts executable
# 7. Create .local/refine-backlog.conf with token + repo
# 8. Create symlink: .local/bin/refine-backlog → installed script
# 9. Run refine-backlog init to create refinement-log.json
# 10. Add refinement-log.json to .gitignore
# 11. Print success message with usage examples

# Usage: ./init-refine-backlog.sh [--repo OWNER/REPO] [--token TOKEN] [--scripts-dir PATH]
```

---

## Part 2: Claude Skill — `refine-backlog`

The skill that performs the actual refinement work.

### Skill Definition

**Name**: `refine-backlog`

**Description**: Intelligently refine GitHub issues to ensure they're dev-ready. Reviews current story state against application context (ADRs, plans, related stories) and historical assumptions to identify gaps, update acceptance criteria, and flag stale assumptions.

**Trigger**: Called by `refine-backlog refine` bash command

### Input Format

The bash script calls Claude with this prompt + context:

```
[System Context]
You are a backlog refinement assistant. Your job is to review GitHub issues and ensure they are "dev-ready" — meaning they have clear acceptance criteria, up-to-date assumptions, and properly scoped work.

You will receive a batch of stories to refine. For each story:
1. Read the current issue body and context (ADRs, plans, related stories)
2. Compare the last refinement snapshot to current app state
3. Identify stale assumptions, missing details, or outdated acceptance criteria
4. Update the issue body to reflect current reality
5. Ensure acceptance criteria are clear, testable, and properly scoped
6. Identify or update dependencies between stories

Return your refinement as JSON (see format below).

[Stories to Refine]
<JSON input from bash script>

[Instructions]
For each story, analyze:

1. **Stale Assumptions**: Compare last_refinement_snapshot to current_app_state.
   - Has deployed version changed? What implications?
   - Have new ADRs been added? Do they affect this story?
   - Have dependent stories been merged? Does that change scope?
   - Example: Story assumed "auth service v1 exists" but v2 was released → update assumptions

2. **Unclear Acceptance Criteria**: 
   - Are they testable? ("User can log in" is vague; "User can submit login form with email + password and receives JWT" is clear)
   - Are there missing edge cases?
   - Do they align with related stories?

3. **Scope Creep or Unclear Scope**:
   - Is this story a good size for one sprint?
   - Should it be split into smaller stories?
   - Are there implicit dependencies not captured?

4. **Dependencies**:
   - Does this story depend on other stories being complete?
   - Do other stories depend on this?
   - Are those dependencies explicitly documented?

5. **Technical Clarity**:
   - Does the story reference relevant ADRs?
   - Are architectural decisions clear?
   - Does it mention any implementation concerns?

Output your analysis as JSON matching the format below. Be concise but thorough. Update the issue body to be clear and dev-ready.

[Output Format]
{
  "refined_stories": [
    {
      "number": 123,
      "refinement_summary": "Brief explanation of what was refined and why",
      "updated_body": "Complete updated issue body. Keep existing structure but update assumptions, AC, and details as needed.",
      "key_changes": [
        "Stale assumption identified: story assumed OAuth provider v1, now v2 is deployed",
        "Clarified AC #2: was 'handle errors' now 'handle 401/403 errors with specific user messaging'",
        "Added dependency note: must be completed before GH-124"
      ],
      "dependencies_to_update": [
        {
          "type": "blocks",
          "story_number": 124,
          "reason": "This story must be complete before GH-124 work begins"
        },
        {
          "type": "blocked_by",
          "story_number": 120,
          "reason": "Depends on database schema from GH-120"
        }
      ],
      "flag_for_discussion": false,
      "flag_details": ""
    }
  ],
  "refinement_notes": "High-level summary of batch. Any patterns noticed across stories?"
}
```

### Claude Skill Template

Create a skill file (`refine-backlog.md` in the skills directory) that:

```markdown
# Backlog Refinement Skill

## Purpose
Refine GitHub issues to ensure they are dev-ready with clear acceptance criteria, current assumptions, and proper dependencies.

## How It Works

You receive a batch of stories with full context:
- Current issue body + metadata
- Relevant ADRs and plan documents
- Related/dependent stories
- Last refinement snapshot (assumptions, app state at that time)
- Current app state (deployed version, completed stories, new ADRs)

For each story, you:
1. Compare last refinement to current state
2. Identify stale assumptions
3. Clarify acceptance criteria
4. Update issue body
5. Identify dependencies

Return JSON with refined stories + notes.

## Input Example
[See "Input Format" section above]

## Output Example
[See "Output Format" section above]

## Key Guidelines

- **Preserve existing issue structure** unless it's confusing. Refining means updating, not rewriting.
- **Be conservative with scope changes**. If a story seems too large, flag it for discussion rather than splitting it yourself.
- **Call out stale assumptions explicitly**. When comparing snapshot to current state, be specific: "Story assumed v1.2 deployed, now v1.2.3 deployed. Impact: X feature is now available, story AC #2 should be updated to leverage it."
- **Keep AC testable**. If AC is vague, make it concrete.
- **Track dependencies**. When you notice implicit dependencies, make them explicit in the output.

## Example Refinement

**Story**: GH-123 "User authentication overhaul"

**Input State**:
- Last refined: 2026-02-28, assumed auth service v1, database migration pending
- Current state: deployed v1.2.3, auth service v2 released, migration complete
- Related stories: GH-120 (merged), GH-124 (blocked_by this story), GH-110 (relates_to)

**Refinement**:
- Stale assumption: Story AC #1 was "support legacy auth tokens". But v2 auth service doesn't support legacy tokens. Update AC to reflect this breaking change.
- New dependency: GH-120 was just merged and released a new database schema. Story's AC #2 assumed this wouldn't be available — now it is. Update AC #2 to use new schema.
- Clarification: AC #3 was "handle errors gracefully". Now be specific: "Return user-friendly error messages for: (1) invalid credentials, (2) account locked, (3) OAuth provider unavailable"
- Dependency update: This story blocks GH-124 and GH-125. Ensure that's documented.

**Output**:
```json
{
  "refined_stories": [
    {
      "number": 123,
      "refinement_summary": "Updated to reflect deployed auth service v2 and completed database migrations. Clarified acceptance criteria with concrete error handling cases.",
      "updated_body": "# User Authentication Overhaul\n\n## Problem\n...",
      "key_changes": [
        "AC #1 updated: legacy auth tokens no longer supported (auth service v2 doesn't support them)",
        "AC #2 updated: now leverages v2-native token refresh endpoint (database migration GH-120 complete)",
        "AC #3 clarified: specific error cases with user-friendly messaging"
      ],
      "dependencies_to_update": [
        {"type": "blocks", "story_number": 124, "reason": "Token refresh endpoint must exist before GH-124"}
      ],
      "flag_for_discussion": false
    }
  ]
}
```
```

---

## Part 3: Integration & Execution Flow

### How bash script calls Claude skill

```bash
# In cmd_refine()
# 1. Gather context for stories needing refinement
context_json=$(gather_context "$repo" "$story_numbers")

# 2. Prepare prompt
system_prompt="<skill definition from refine-backlog.md>"
user_prompt="Refine these stories:\n\n$context_json"

# 3. Call Claude (via API or CLI tool, depending on setup)
# Option A: Use anthropic SDK
# Option B: Use curl to call Claude API directly
# Option C: Use a wrapper script that invokes Claude

refinement_result=$(call_claude "$system_prompt" "$user_prompt")

# 4. Parse results (JSON)
# refinement_result is JSON with refined_stories array

# 5. For each refined story:
for story in $(echo "$refinement_result" | jq '.refined_stories[]'); do
  number=$(echo "$story" | jq '.number')
  updated_body=$(echo "$story" | jq '.updated_body')
  
  # Update GitHub
  github_update_issue "$repo" "$number" "{\"body\": \"$updated_body\"}"
  github_remove_label "$repo" "$number" "needs-refinement"
  github_add_label "$repo" "$number" "dev-ready"
  
  # Update log
  update_story_refinement "$log_file" "$number" "$story"
done

# 6. Summary
log_info "Refined ${#stories[@]} stories"
```

### Calling Claude

Options for `call_claude()` function:

**Option 1: Direct API call** (if bash script can make HTTPS calls)
```bash
call_claude(system_prompt, user_prompt) {
  # Use curl to POST to https://api.anthropic.com/v1/messages
  # Requires ANTHROPIC_API_KEY env var
  # Returns JSON response
}
```

**Option 2: Claude CLI wrapper** (if Claude CLI is available)
```bash
call_claude(system_prompt, user_prompt) {
  # Write prompts to temp files
  # Call `claude --system <file> <file>` 
  # Parse and return output
}
```

**Option 3: Artifact-based** (if running from Claude.ai)
```bash
# The bash scripts would be run from within an artifact
# And call Claude via the JavaScript API
# Not applicable for full CLI tool, but mentioned for completeness
```

For v1, recommend **Option 1** (direct API) or **Option 2** (CLI wrapper), depending on your setup.

---

## Part 4: Testing Strategy

### Unit Tests

For each bash function:

```bash
# test/lib/test-common.sh
test_log_info() { ... }
test_json_merge() { ... }

# test/lib/test-github-api.sh
test_github_get_issues() { ... }
test_github_add_label() { ... }

# test/lib/test-backlog-analysis.sh
test_analyze_backlog_with_label() { ... }
test_analyze_backlog_with_age() { ... }

# Run: bash test/run-all-tests.sh
```

### Integration Tests

Test full workflows:

```bash
# test/integration/test-init.sh
test_init_creates_log_file() { ... }
test_init_adds_to_gitignore() { ... }

# test/integration/test-check.sh
test_check_identifies_needs_refinement() { ... }
test_check_output_format() { ... }

# test/integration/test-refine.sh
test_refine_updates_github() { ... }
test_refine_updates_log() { ... }
test_refine_handles_errors() { ... }
```

### Test Repo Validation

In the test repo (separate GitHub repo for testing):
1. Initialize system
2. Create 5-10 sample issues with different states
3. Run `refine-backlog check` — verify output
4. Manually mark some as "needs-refinement"
5. Run `refine-backlog refine --all` with mocked Claude (return fixed JSON)
6. Verify GitHub updates work correctly
7. Verify refinement-log.json is updated correctly
8. Run check again, verify no false positives

---

## Part 5: Configuration & Installation

### Config File (`~/.local/refine-backlog.conf`)

```bash
# GitHub credentials
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# Default repo (can be overridden per repo)
DEFAULT_REPO="owner/repo-name"

# Claude API key (if using direct API call)
ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxx"

# Logging level
LOG_LEVEL="info"  # info, debug, error

# Paths
ADR_PATTERNS=("docs/adr/ADR-*.md" "adr/*.md")
PLAN_PATTERNS=("planning/*-plan.md" "docs/planning/*-plan.md")

# Refinement triggers
MIN_DAYS_TO_REFINEMENT=28
BATCH_SIZE=10  # Max stories per Claude call
```

### .gitignore additions

```
# Refinement system
.local/refine-backlog.conf  # Don't commit tokens
refinement-log.json.lock    # Lock files
```

---

## Success Criteria

✅ All bash functions work correctly (tested, error handling)
✅ `refine-backlog init` successfully initializes a repo
✅ `refine-backlog check` identifies stories needing refinement without LLM calls
✅ `refine-backlog refine` successfully calls Claude and updates GitHub
✅ Refinement-log.json is correctly updated after each refinement
✅ Integration tests pass
✅ Test repo validation passes
✅ Documentation is clear and complete

---

## Notes for Implementation

- **Error handling is critical**: Network failures, GitHub rate limits, malformed responses must be handled gracefully
- **Logging**: Every significant action should be logged for auditability
- **Validation**: Validate GitHub token early, validate repo access before proceeding
- **Atomicity**: Use temp files and atomic moves to prevent corruption
- **Dry-run mode**: Always provide --dry-run flag to preview changes before applying
- **Idempotency**: Running refinement twice should be safe (don't double-update if already refined)
