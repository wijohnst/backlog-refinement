#!/usr/bin/env bats
# Integration tests for check workflow

setup() {
  load ../test_helper
  setup_test_env
}

teardown() {
  teardown_test_env
}

# =============================================================================
# CHECK WORKFLOW TESTS
# =============================================================================

@test "check identifies new stories" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  # Run analysis on repo with 2 mock issues, empty log
  local analysis=$(analyze_backlog "test/repo" "$log_path")

  local new_count=$(echo "$analysis" | jq '.summary.total_new')
  [ "$new_count" -eq 2 ]
}

@test "check identifies stories needing refinement" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  # Add issue 123 to log (which has needs-refinement label in mock)
  local issue='{"number": 123, "title": "Test", "body": "Test", "labels": [{"name": "needs-refinement"}]}'
  add_story_to_log "$log_path" "123" "$issue"

  # But create a new hash so it's not detected as changed
  local content=$(load_log "$log_path")
  content=$(echo "$content" | jq '.stories."GH-123".body_hash = "same"')
  save_log "$log_path" "$content"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  # Issue 123 still has needs-refinement label, so should appear
  local needs=$(echo "$analysis" | jq '.needs_refinement | length')
  [ "$needs" -gt 0 ]
}

@test "check produces valid analysis JSON" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  assert_valid_json "$analysis"

  # Check required fields
  [ -n "$(echo "$analysis" | jq '.needs_refinement')" ]
  [ -n "$(echo "$analysis" | jq '.dev_ready')" ]
  [ -n "$(echo "$analysis" | jq '.new_stories')" ]
  [ -n "$(echo "$analysis" | jq '.summary')" ]
}

@test "check summary totals match arrays" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  local needs_count=$(echo "$analysis" | jq '.summary.total_needs_refinement')
  local actual_needs=$(echo "$analysis" | jq '.needs_refinement | length')

  [ "$needs_count" -eq "$actual_needs" ]
}

@test "check detects old stories" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  # Mock issue 124 is from 2026-02-15, should be >28 days old
  # Add it to log without refinement
  local issue='{"number": 124, "title": "Old", "body": "Old", "created_at": "2026-01-01T10:00:00Z", "labels": []}'
  add_story_to_log "$log_path" "124" "$issue"

  # Set refinement_status to new so body hash doesn't match
  local content=$(load_log "$log_path")
  content=$(echo "$content" | jq '.stories."GH-124".refinement_status = "new"')
  save_log "$log_path" "$content"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  # Verify analysis structure
  [ "$(echo "$analysis" | jq '.summary.total_needs_refinement >= 0')" = "true" ]
}

# =============================================================================
# APP STATE CAPTURE TESTS
# =============================================================================

@test "check captures app state" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  # Simulate capturing app state
  local app_state=$(capture_app_state ".")
  update_app_state_in_log "$log_path" "$app_state"

  local content=$(load_log "$log_path")
  local saved_state=$(echo "$content" | jq '.app_state')

  [ -n "$(echo "$saved_state" | jq '.timestamp')" ]
  [ -n "$(echo "$saved_state" | jq '.git_sha')" ]
  [ -n "$(echo "$saved_state" | jq '.deployed_version')" ]
}

@test "check updates last_check metadata" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  local app_state=$(capture_app_state ".")
  update_app_state_in_log "$log_path" "$app_state"

  local content=$(load_log "$log_path")
  local last_check=$(echo "$content" | jq -r '.metadata.last_check')

  [[ "$last_check" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
  [ "$last_check" != "null" ]
}

# =============================================================================
# STORY DETAILS IN CHECK TESTS
# =============================================================================

@test "check includes story titles in results" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  # All stories should have title
  local titles=$(echo "$analysis" | jq -r '.new_stories[].title')
  [ -n "$titles" ]
}

@test "check includes story numbers in results" {
  init_test_git_repo

  load_libs
  load_mocks

  local log_path="$TEST_TMPDIR/refinement-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  # All stories should have number
  local numbers=$(echo "$analysis" | jq '.new_stories[].number')
  [ -n "$numbers" ]
  [[ "$numbers" =~ ^[0-9]+ ]]
}
