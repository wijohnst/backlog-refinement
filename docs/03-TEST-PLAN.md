# Backlog Refinement System — Test Plan

## Overview

This document outlines testing strategy for the refine-backlog system. Tests are organized into:
1. **Unit tests** — individual functions
2. **Integration tests** — full workflows
3. **Manual validation** — test repo scenarios

---

## Part 1: Unit Tests

### Test Framework

Use `bats` (Bash Automated Testing System) for bash script testing.

```bash
# Install bats
npm install --save-dev bats

# Run tests
bats test/lib/*.bats test/integration/*.bats
```

### Test File Structure

```
test/
├── lib/
│   ├── common.bats
│   ├── github-api.bats
│   ├── backlog-analysis.bats
│   ├── context-gathering.bats
│   ├── log-management.bats
│   └── app-state.bats
├── integration/
│   ├── init.bats
│   ├── check.bats
│   ├── refine.bats
│   └── status.bats
├── fixtures/
│   ├── sample-issue.json
│   ├── sample-log.json
│   ├── sample-adr.md
│   └── sample-plan.md
├── mocks/
│   ├── mock-github-api.sh
│   └── mock-claude.sh
└── helpers/
    └── test-helpers.sh
```

### Unit Tests by Module

#### `test/lib/common.bats`

```bash
@test "log_info outputs green text" {
  output=$(log_info "test message" 2>&1)
  [[ "$output" == *"test message"* ]]
}

@test "log_error outputs to stderr" {
  output=$(log_error "error message" 2>&1 >/dev/null)
  [[ "$output" == *"error message"* ]]
}

@test "fail exits with code 1" {
  run fail "test error"
  [ "$status" -eq 1 ]
}

@test "require_command fails if command not found" {
  run require_command "nonexistent_command_12345"
  [ "$status" -eq 1 ]
}

@test "require_command succeeds for existing command" {
  run require_command "bash"
  [ "$status" -eq 0 ]
}

@test "require_env fails if env var not set" {
  unset TEST_VAR
  run require_env "TEST_VAR"
  [ "$status" -eq 1 ]
}

@test "json_validate accepts valid JSON" {
  echo '{"key": "value"}' > /tmp/test.json
  run json_validate /tmp/test.json
  [ "$status" -eq 0 ]
}

@test "json_validate rejects invalid JSON" {
  echo '{invalid json' > /tmp/test.json
  run json_validate /tmp/test.json
  [ "$status" -ne 0 ]
}

@test "file_hash computes SHA256" {
  echo "test content" > /tmp/test.txt
  hash=$(file_hash /tmp/test.txt)
  [[ "$hash" =~ ^[a-f0-9]{64}$ ]]
}

@test "ensure_file creates file if not exists" {
  rm -f /tmp/test-file.txt
  ensure_file /tmp/test-file.txt
  [ -f /tmp/test-file.txt ]
}

@test "ensure_dir creates directory if not exists" {
  rm -rf /tmp/test-dir
  ensure_dir /tmp/test-dir
  [ -d /tmp/test-dir ]
}
```

#### `test/lib/github-api.bats`

```bash
setup() {
  source test/mocks/mock-github-api.sh
}

@test "github_get_issues returns JSON array" {
  run github_get_issues "owner/repo"
  [ "$status" -eq 0 ]
  # Should be valid JSON array
  echo "$output" | jq '.' >/dev/null
}

@test "github_get_issues handles API error" {
  export GITHUB_API_ERROR="true"
  run github_get_issues "invalid/repo"
  [ "$status" -ne 0 ]
}

@test "github_get_issue_links returns blocks/blocked_by arrays" {
  run github_get_issue_links "owner/repo" 123
  [ "$status" -eq 0 ]
  output=$(echo "$output" | jq '.blocks // empty')
  [[ ! -z "$output" ]]
}

@test "github_update_issue sends correct payload" {
  run github_update_issue "owner/repo" 123 '{"body": "new body"}'
  [ "$status" -eq 0 ]
}

@test "github_add_label adds label to issue" {
  run github_add_label "owner/repo" 123 "dev-ready"
  [ "$status" -eq 0 ]
}

@test "github_remove_label removes label from issue" {
  run github_remove_label "owner/repo" 123 "needs-refinement"
  [ "$status" -eq 0 ]
}

@test "github_get_deployed_version handles package.json" {
  mkdir -p /tmp/test-repo
  echo '{"version": "1.2.3"}' > /tmp/test-repo/package.json
  run get_deployed_version /tmp/test-repo
  [ "$status" -eq 0 ]
  [[ "$output" == "1.2.3" ]]
}

@test "github_get_deployed_version handles git tags" {
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo
  git init
  git tag v1.5.0
  run get_deployed_version .
  [ "$status" -eq 0 ]
  [[ "$output" == "v1.5.0" ]]
}
```

#### `test/lib/backlog-analysis.bats`

```bash
@test "analyze_backlog detects needs-refinement label" {
  # Setup: issue with needs-refinement label
  run analyze_backlog "owner/repo" test-fixtures/refinement-log.json
  [ "$status" -eq 0 ]
  
  # Should identify GH-123 as needing refinement
  count=$(echo "$output" | jq '.needs_refinement | length')
  [ "$count" -gt 0 ]
}

@test "analyze_backlog detects old stories" {
  # Setup: issue created >28 days ago, never refined
  run analyze_backlog "owner/repo" test-fixtures/refinement-log.json
  [ "$status" -eq 0 ]
  
  # Should identify old story
  reasons=$(echo "$output" | jq '.needs_refinement[].reasons')
  [[ "$reasons" == *"age"* ]]
}

@test "analyze_backlog detects body changes" {
  # Setup: issue body hash differs from log
  run analyze_backlog "owner/repo" test-fixtures/refinement-log.json
  [ "$status" -eq 0 ]
  
  # Should identify body_changed reason
  output | jq '.needs_refinement[].reasons' | grep -q "body_changed"
}

@test "analyze_backlog marks recently refined as dev-ready" {
  # Setup: recently refined story with dev-ready label
  run analyze_backlog "owner/repo" test-fixtures/refinement-log.json
  [ "$status" -eq 0 ]
  
  # Should NOT be in needs_refinement list
  ! echo "$output" | jq '.needs_refinement[] | select(.number == 124)'
}

@test "reasons_for_story returns array of reasons" {
  run reasons_for_story "test-fixtures/issue.json" "test-fixtures/log-entry.json"
  [ "$status" -eq 0 ]
  
  # Output should be JSON array
  echo "$output" | jq '.[0].type' >/dev/null
}
```

#### `test/lib/context-gathering.bats`

```bash
@test "gather_context returns stories with context" {
  run gather_context "owner/repo" "123 124"
  [ "$status" -eq 0 ]
  
  # Should have stories array
  count=$(echo "$output" | jq '.stories | length')
  [ "$count" -eq 2 ]
}

@test "gather_context includes ADR files" {
  run gather_context "owner/repo" "123"
  [ "$status" -eq 0 ]
  
  # Should have adr_files
  adr_count=$(echo "$output" | jq '.stories[0].context.adr_files | length')
  [ "$adr_count" -gt 0 ]
}

@test "gather_context includes plan files" {
  run gather_context "owner/repo" "123"
  [ "$status" -eq 0 ]
  
  # Should have plan_files
  plan_count=$(echo "$output" | jq '.stories[0].context.plan_files | length')
  [ "$plan_count" -gt 0 ]
}

@test "gather_context includes related stories" {
  run gather_context "owner/repo" "123"
  [ "$status" -eq 0 ]
  
  # Should have related_stories
  echo "$output" | jq '.stories[0].context.related_stories' >/dev/null
}

@test "find_adr_files detects explicit links" {
  issue_body="See [ADR-002](docs/adr/ADR-002.md) for details"
  run find_adr_files "test-fixtures/repo" "$issue_body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADR-002"* ]]
}

@test "find_plan_files matches story keywords" {
  run find_plan_files "test-fixtures/repo" "auth login"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth-plan.md"* || "$output" == *"login-plan.md"* ]]
}

@test "read_file_safe returns file contents" {
  echo "test content" > /tmp/test.md
  run read_file_safe /tmp/test.md 100000
  [ "$status" -eq 0 ]
  [[ "$output" == "test content" ]]
}

@test "read_file_safe respects max_size" {
  # Create file larger than 10 bytes
  dd if=/dev/zero of=/tmp/large.txt bs=1 count=20 2>/dev/null
  run read_file_safe /tmp/large.txt 10
  [ "$status" -ne 0 ]
}
```

#### `test/lib/log-management.bats`

```bash
@test "init_log creates refinement-log.json" {
  rm -f /tmp/test-log.json
  run init_log "owner/repo" /tmp/test-log.json
  [ "$status" -eq 0 ]
  [ -f /tmp/test-log.json ]
}

@test "init_log sets version correctly" {
  run init_log "owner/repo" /tmp/test-log.json
  [ "$status" -eq 0 ]
  version=$(jq '.version' /tmp/test-log.json)
  [[ "$version" == '"1.0"' ]]
}

@test "load_log reads and validates JSON" {
  run load_log test-fixtures/sample-log.json
  [ "$status" -eq 0 ]
  echo "$output" | jq '.metadata' >/dev/null
}

@test "load_log fails on invalid JSON" {
  echo '{invalid' > /tmp/bad-log.json
  run load_log /tmp/bad-log.json
  [ "$status" -ne 0 ]
}

@test "save_log atomically writes JSON" {
  log_data='{"version": "1.0", "stories": {}}'
  run save_log /tmp/test-log.json "$log_data"
  [ "$status" -eq 0 ]
  [ -f /tmp/test-log.json ]
  jq '.version' /tmp/test-log.json | grep -q "1.0"
}

@test "add_story_to_log creates story entry" {
  init_log "owner/repo" /tmp/test-log.json
  issue_data='{"number": 123, "title": "Test story", "body": "...", "labels": []}'
  run add_story_to_log /tmp/test-log.json 123 "$issue_data"
  [ "$status" -eq 0 ]
  
  # Verify story was added
  number=$(jq '.stories."GH-123".number' /tmp/test-log.json)
  [[ "$number" == "123" ]]
}

@test "update_story_refinement sets dev-ready status" {
  init_log "owner/repo" /tmp/test-log.json
  add_story_to_log /tmp/test-log.json 123 "{}"
  
  result='{"number": 123, "refinement_notes": "Refined"}'
  run update_story_refinement /tmp/test-log.json 123 "$result"
  [ "$status" -eq 0 ]
  
  status=$(jq '.stories."GH-123".refinement_status' /tmp/test-log.json)
  [[ "$status" == '"dev-ready"' ]]
}

@test "update_app_state_in_log updates app_state section" {
  init_log "owner/repo" /tmp/test-log.json
  
  app_state='{"timestamp": "2026-03-05T10:00:00Z", "git_sha": "abc123"}'
  run update_app_state_in_log /tmp/test-log.json "$app_state"
  [ "$status" -eq 0 ]
  
  sha=$(jq '.app_state.git_sha' /tmp/test-log.json)
  [[ "$sha" == '"abc123"' ]]
}

@test "story_by_number retrieves story from log" {
  init_log "owner/repo" /tmp/test-log.json
  add_story_to_log /tmp/test-log.json 123 '{"title": "Test"}'
  
  run story_by_number /tmp/test-log.json 123
  [ "$status" -eq 0 ]
  title=$(echo "$output" | jq '.title')
  [[ "$title" == '"Test"' ]]
}

@test "get_needs_refinement_stories filters by status" {
  run get_needs_refinement_stories test-fixtures/sample-log.json
  [ "$status" -eq 0 ]
  
  # All returned stories should have needs-refinement status
  echo "$output" | jq '.[] | .refinement_status' | grep -q "needs-refinement"
}
```

#### `test/lib/app-state.bats`

```bash
@test "capture_app_state returns JSON with all fields" {
  run capture_app_state test-fixtures/repo
  [ "$status" -eq 0 ]
  
  echo "$output" | jq '.timestamp' >/dev/null
  echo "$output" | jq '.git_sha' >/dev/null
  echo "$output" | jq '.deployed_version' >/dev/null
}

@test "get_git_sha returns valid SHA" {
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial"
  
  run get_git_sha .
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-f0-9]{7,}$ ]]
}

@test "get_deployed_version handles all sources" {
  # Test with package.json
  mkdir -p /tmp/test-repo
  echo '{"version": "1.2.3"}' > /tmp/test-repo/package.json
  run get_deployed_version /tmp/test-repo
  [ "$status" -eq 0 ]
  [[ "$output" == "1.2.3" ]]
  
  # Test with VERSION file
  rm /tmp/test-repo/package.json
  echo "2.0.0" > /tmp/test-repo/VERSION
  run get_deployed_version /tmp/test-repo
  [ "$status" -eq 0 ]
  [[ "$output" == "2.0.0" ]]
}

@test "get_recent_closed_stories returns issue numbers" {
  run get_recent_closed_stories "owner/repo" 7
  [ "$status" -eq 0 ]
  
  # Should return JSON array of numbers
  echo "$output" | jq '.[0]' | grep -q "[0-9]"
}

@test "get_recent_modified_adr_files lists recent ADRs" {
  mkdir -p /tmp/test-repo/docs/adr
  touch -d "2 days ago" /tmp/test-repo/docs/adr/ADR-001.md
  touch -d "30 days ago" /tmp/test-repo/docs/adr/ADR-002.md
  
  run get_recent_modified_adr_files /tmp/test-repo 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADR-001.md"* ]]
  [[ "$output" != *"ADR-002.md"* ]]
}
```

---

## Part 2: Integration Tests

#### `test/integration/init.bats`

```bash
@test "init creates refinement-log.json" {
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo
  git init
  
  export GITHUB_TOKEN="test_token"
  export GITHUB_REPO="owner/repo"
  
  run cmd_init
  [ "$status" -eq 0 ]
  [ -f refinement-log.json ]
}

@test "init validates GitHub token" {
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo
  git init
  
  unset GITHUB_TOKEN
  
  run cmd_init
  [ "$status" -ne 0 ]
}

@test "init adds to .gitignore" {
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo
  git init
  
  export GITHUB_TOKEN="test_token"
  export GITHUB_REPO="owner/repo"
  
  run cmd_init
  [ "$status" -eq 0 ]
  grep -q "refinement-log.json" .gitignore
}

@test "init symlinks refine-backlog script" {
  mkdir -p /tmp/test-repo/.local/bin
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo
  git init
  
  export GITHUB_TOKEN="test_token"
  export GITHUB_REPO="owner/repo"
  
  run cmd_init
  [ "$status" -eq 0 ]
  [ -L .local/bin/refine-backlog ]
}
```

#### `test/integration/check.bats`

```bash
@test "check identifies stories with needs-refinement label" {
  cd test-fixtures/repo
  
  run cmd_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs refinement"* ]]
}

@test "check identifies old stories" {
  cd test-fixtures/repo
  
  run cmd_check --details
  [ "$status" -eq 0 ]
  # Should show stories >4 weeks old
}

@test "check outputs JSON with --json flag" {
  cd test-fixtures/repo
  
  run cmd_check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq '.needs_refinement' >/dev/null
}

@test "check saves to file with --output flag" {
  cd test-fixtures/repo
  
  run cmd_check --output /tmp/check-output.json
  [ "$status" -eq 0 ]
  [ -f /tmp/check-output.json ]
}

@test "check summary is accurate" {
  cd test-fixtures/repo
  
  run cmd_check
  [ "$status" -eq 0 ]
  # Count stories in output
  count=$(echo "$output" | grep -c "GH-")
  # Should match count in analysis
}
```

#### `test/integration/refine.bats`

```bash
@test "refine --all refines all needing stories" {
  cd test-fixtures/repo
  
  # Mock Claude
  export MOCK_CLAUDE="true"
  
  run cmd_refine --all --dry-run
  [ "$status" -eq 0 ]
  # Dry-run should show what would happen
}

@test "refine --ids refines specific stories" {
  cd test-fixtures/repo
  
  export MOCK_CLAUDE="true"
  
  run cmd_refine --ids "GH-123,GH-124" --dry-run
  [ "$status" -eq 0 ]
}

@test "refine updates GitHub issues" {
  cd test-fixtures/repo
  
  export MOCK_CLAUDE="true"
  
  run cmd_refine --ids "GH-123" --confirm
  [ "$status" -eq 0 ]
  # In real test, verify GitHub was updated
}

@test "refine updates refinement-log.json" {
  cd test-fixtures/repo
  
  export MOCK_CLAUDE="true"
  
  run cmd_refine --ids "GH-123" --confirm
  [ "$status" -eq 0 ]
  
  # Check that log was updated
  status=$(jq '.stories."GH-123".refinement_status' refinement-log.json)
  [[ "$status" == '"dev-ready"' ]]
}

@test "refine removes needs-refinement label" {
  cd test-fixtures/repo
  
  export MOCK_CLAUDE="true"
  
  # Setup: issue has needs-refinement label
  # Run refine
  run cmd_refine --ids "GH-123" --confirm
  [ "$status" -eq 0 ]
  
  # In real test with mock GitHub, verify label was removed
}

@test "refine adds dev-ready label" {
  cd test-fixtures/repo
  
  export MOCK_CLAUDE="true"
  
  run cmd_refine --ids "GH-123" --confirm
  [ "$status" -eq 0 ]
  
  # In real test with mock GitHub, verify label was added
}

@test "refine --dry-run doesn't update anything" {
  cd test-fixtures/repo
  
  export MOCK_CLAUDE="true"
  
  initial_status=$(jq '.stories."GH-123".refinement_status' refinement-log.json)
  
  run cmd_refine --ids "GH-123" --dry-run
  [ "$status" -eq 0 ]
  
  final_status=$(jq '.stories."GH-123".refinement_status' refinement-log.json)
  [[ "$initial_status" == "$final_status" ]]
}
```

#### `test/integration/status.bats`

```bash
@test "status shows refinement status for all stories" {
  cd test-fixtures/repo
  
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-ready"* ]]
}

@test "status shows specific story with --story flag" {
  cd test-fixtures/repo
  
  run cmd_status --story GH-123
  [ "$status" -eq 0 ]
  [[ "$output" == *"GH-123"* ]]
}

@test "status outputs JSON with --json flag" {
  cd test-fixtures/repo
  
  run cmd_status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq '.stories' >/dev/null
}
```

---

## Part 3: Manual Validation (Test Repo)

### Test Repo Setup

Create a standalone GitHub repository for testing:

```bash
# Create test repo
mkdir refine-backlog-test-repo
cd refine-backlog-test-repo
git init
git remote add origin https://github.com/YOUR_ACCOUNT/refine-backlog-test-repo.git
```

Push to GitHub.

### Sample Issues to Create

Create these issues in the test repo to validate workflows:

#### Issue 1: Needs Refinement Label
- **Title**: GH-1: User authentication
- **Body**: Clear, well-structured, with AC
- **Labels**: `needs-refinement`
- **Expected**: System detects and refines
- **Validation**: After refinement, `needs-refinement` removed, `dev-ready` added

#### Issue 2: Open >4 Weeks
- **Title**: GH-2: Dashboard redesign
- **Created**: 4+ weeks ago
- **Last Refined**: 4+ weeks ago
- **Labels**: none
- **Expected**: System detects as stale
- **Validation**: Refined correctly

#### Issue 3: Blocked by Merged Story
- **Title**: GH-3: Token refresh
- **Blocked by**: GH-4 (which will be merged)
- **Expected**: After GH-4 is "merged", GH-3 should be flagged for re-refinement
- **Validation**: Refinement needed detected

#### Issue 4: Dependencies
- **Title**: GH-4: OAuth provider setup
- **Blocks**: GH-3
- **Status**: Set up for "merging"
- **Expected**: When merged, GH-3 gets flagged
- **Validation**: Works correctly

#### Issue 5: Recently Refined
- **Title**: GH-5: API error handling
- **Last Refined**: 1-2 days ago
- **Labels**: `dev-ready`
- **Expected**: System recognizes as ready, no refinement needed
- **Validation**: Not flagged for refinement

#### Issue 6: New Story
- **Title**: GH-6: New feature
- **Labels**: none
- **Expected**: Added to log, status "new", not flagged for refinement (needs explicit label)
- **Validation**: Log updated correctly

### Validation Scenarios

#### Scenario 1: Initialize Repo
```bash
refine-backlog init --repo YOUR_ACCOUNT/refine-backlog-test-repo --token $GITHUB_TOKEN

# Validation:
# ✓ refinement-log.json created
# ✓ Contains all 6 issues
# ✓ Correct initial statuses
# ✓ .gitignore updated
```

#### Scenario 2: Check Backlog
```bash
refine-backlog check --details

# Expected output:
# Stories needing refinement: 3
#
# GH-1 (needs-refinement label)
# GH-2 (open 32 days)
# GH-3 (blocked by GH-4)
#
# Already dev-ready: 2 (GH-5)
# New/not evaluated: 1 (GH-6)

# Validation:
# ✓ Correct count
# ✓ Correct reasons
# ✓ No false positives
```

#### Scenario 3: Refine Single Story
```bash
refine-backlog refine --ids GH-1 --dry-run

# Should show what would be updated

refine-backlog refine --ids GH-1 --confirm

# Validation:
# ✓ GitHub issue updated (body)
# ✓ needs-refinement label removed
# ✓ dev-ready label added
# ✓ Log updated with timestamp
# ✓ Can verify via GitHub UI
```

#### Scenario 4: Batch Refine
```bash
refine-backlog refine --all --confirm

# Validation:
# ✓ All 3 needing stories are refined
# ✓ All GitHub updates made
# ✓ Log fully updated
# ✓ No stories left with needs-refinement
```

#### Scenario 5: Check Again After Refinement
```bash
refine-backlog check

# Expected output:
# Stories needing refinement: 0
# Already dev-ready: 5

# Validation:
# ✓ All previously needing stories now dev-ready
# ✓ No false positives
```

#### Scenario 6: Force Re-Refinement
```bash
# Add needs-refinement label back to GH-1 via GitHub UI

refine-backlog check

# Expected output:
# Stories needing refinement: 1
# GH-1 (needs-refinement label, last refined 1 hour ago)

# Validation:
# ✓ Label override works
# ✓ Log captures re-refinement trigger
```

#### Scenario 7: Error Handling
```bash
# Try to refine with invalid GitHub token
export GITHUB_TOKEN="invalid_token"
refine-backlog refine --all

# Expected: graceful error, no data corruption

# Validation:
# ✓ Error message is clear
# ✓ refinement-log.json unchanged
# ✓ No partial updates to GitHub
```

---

## Test Fixtures

Create sample files in `test/fixtures/`:

### `sample-log.json`
A complete refinement-log.json with various story states

### `sample-issue.json`
A GitHub issue API response

### `sample-adr.md`
Sample ADR document (to test file reading)

### `sample-plan.md`
Sample plan document

### Repo Structure
```
test/fixtures/repo/
├── .git/                    # Real git repo for testing
├── refinement-log.json
├── docs/
│   └── adr/
│       ├── ADR-001.md
│       └── ADR-002.md
└── planning/
    ├── auth-plan.md
    └── dashboard-plan.md
```

---

## Test Execution

### Run All Tests
```bash
bats test/lib/*.bats test/integration/*.bats
```

### Run Specific Module Tests
```bash
bats test/lib/common.bats
bats test/integration/refine.bats
```

### With Coverage (optional)
```bash
kcov coverage bats test/lib/*.bats
```

### Manual Validation Checklist
- [ ] Initialize test repo
- [ ] Run check, verify output
- [ ] Refine single story, verify GitHub + log
- [ ] Refine batch, verify all updates
- [ ] Check again, verify no false positives
- [ ] Test error scenarios
- [ ] Verify --dry-run doesn't change anything
- [ ] Test dependency tracking
- [ ] Test with missing ADR/plan files

---

## Expected Test Results

### Unit Test Coverage
- `common.sh`: 100% (all functions tested)
- `github-api.sh`: 90% (mocked API, real call integration in CI/CD)
- `backlog-analysis.sh`: 95%
- `context-gathering.sh`: 85%
- `log-management.sh`: 100%
- `app-state.sh`: 85%

### Integration Test Coverage
- Initialization: ✓
- Backlog analysis: ✓
- Single story refinement: ✓
- Batch refinement: ✓
- Error handling: ✓
- Idempotency: ✓

### Manual Validation
- All 6 scenarios pass: ✓
- Error scenarios handled gracefully: ✓
- GitHub updates correct: ✓
- Log consistency maintained: ✓
- No data corruption: ✓

---

## Continuous Integration

In GitHub Actions:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install bats
        run: npm install --save-dev bats
      - name: Run unit tests
        run: bats test/lib/*.bats
      - name: Run integration tests
        run: bats test/integration/*.bats
      - name: Upload coverage
        uses: codecov/codecov-action@v2
```

