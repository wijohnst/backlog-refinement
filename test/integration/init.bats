#!/usr/bin/env bats
# Integration tests for init workflow

setup() {
  load ../test_helper
  setup_test_env
}

teardown() {
  teardown_test_env
}

# =============================================================================
# INITIALIZATION WORKFLOW TESTS
# =============================================================================

@test "init creates refinement log" {
  init_test_git_repo

  # Simulate init by sourcing libs and calling init_log
  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  [ -f "$log_path" ]
}

@test "init log has valid v1.0 structure" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local content=$(cat "$log_path")
  local version=$(echo "$content" | jq -r '.version')
  local repo=$(echo "$content" | jq -r '.metadata.repo')

  [ "$version" = "1.0" ]
  [ "$repo" = "test/repo" ]
}

@test "init log has metadata fields" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local content=$(cat "$log_path")
  local metadata=$(echo "$content" | jq '.metadata')

  [[ "$(echo "$metadata" | jq -r '.initialized_at')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
  [ "$(echo "$metadata" | jq -r '.last_check')" = "null" ]
  [ "$(echo "$metadata" | jq -r '.last_refinement')" = "null" ]
}

@test "init log has app_state section" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local content=$(cat "$log_path")
  local app_state=$(echo "$content" | jq '.app_state')

  # app_state should be empty object initially
  [ "$app_state" = "{}" ]
}

@test "init log has empty stories object" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local content=$(cat "$log_path")
  local stories=$(echo "$content" | jq '.stories')

  [ "$stories" = "{}" ]
}

# =============================================================================
# GIT REPO VALIDATION TESTS
# =============================================================================

@test "works in git repository" {
  init_test_git_repo

  load_libs

  # Should not fail when git repo exists
  run bash -c "cd $TEST_TMPDIR && git rev-parse --git-dir > /dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "detects git remote for repository" {
  init_test_git_repo
  unset GITHUB_REPO  # Ensure fallback to git remote detection

  load_libs

  local repo=$(github_repo)
  [ "$repo" = "test/repo" ]
}

# =============================================================================
# LOG INITIALIZATION WITH MULTIPLE STORIES TESTS
# =============================================================================

@test "can add stories to initialized log" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local issue1='{"number": 100, "title": "Issue 1", "body": "Body 1"}'
  local issue2='{"number": 101, "title": "Issue 2", "body": "Body 2"}'

  add_story_to_log "$log_path" "100" "$issue1"
  add_story_to_log "$log_path" "101" "$issue2"

  local content=$(cat "$log_path")
  local count=$(echo "$content" | jq '.stories | length')

  [ "$count" -eq 2 ]
}

@test "stories in log have required fields" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local issue='{"number": 100, "title": "Test", "body": "Body"}'
  add_story_to_log "$log_path" "100" "$issue"

  local content=$(cat "$log_path")
  local story=$(echo "$content" | jq '.stories."GH-100"')

  [ "$(echo "$story" | jq -r '.number')" = "100" ]
  [ "$(echo "$story" | jq -r '.refinement_status')" = "new" ]
  [ -n "$(echo "$story" | jq -r '.body_hash')" ]
  [ "$(echo "$story" | jq -r '.dependencies.blocks | type')" = '"array"' ]
}

# =============================================================================
# LOG PERSISTENCE TESTS
# =============================================================================

@test "log survives save and load cycle" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  local issue='{"number": 123, "title": "Test", "body": "Body"}'
  add_story_to_log "$log_path" "123" "$issue"

  # Load and verify
  local content=$(load_log "$log_path")
  local story=$(echo "$content" | jq '.stories."GH-123"')

  [ "$(echo "$story" | jq -r '.title')" = "Test" ]
}

@test "atomic writes prevent corruption" {
  init_test_git_repo

  load_libs
  local log_path="$TEST_TMPDIR/refinement-log.json"

  init_log "test/repo" "$log_path"

  # Write multiple times
  for i in {1..5}; do
    local app_state="{\"timestamp\": \"2026-03-0${i}T10:00:00Z\"}"
    update_app_state_in_log "$log_path" "$app_state"
  done

  # Log should still be valid JSON
  local content=$(cat "$log_path")
  echo "$content" | jq empty
}
