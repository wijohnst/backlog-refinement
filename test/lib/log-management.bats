#!/usr/bin/env bats
# Tests for lib/log-management.sh

setup() {
  load ../test_helper
  load_common
  load_mocks
  source "$REFINE_BACKLOG_DIR/lib/log-management.sh"
  setup_test_env
}

teardown() {
  teardown_test_env
}

# =============================================================================
# LOG INITIALIZATION TESTS
# =============================================================================

@test "init_log creates valid log file" {
  local log_path="$TEST_TMPDIR/test-log.json"

  init_log "test/repo" "$log_path"

  [ -f "$log_path" ]
  local content=$(cat "$log_path")
  assert_valid_json "$content"
}

@test "init_log sets correct version" {
  local log_path="$TEST_TMPDIR/test-log.json"

  init_log "test/repo" "$log_path"

  local content=$(cat "$log_path")
  local version=$(json_get "$content" '.version')
  [ "$version" = "1.0" ]
}

@test "init_log sets repo name" {
  local log_path="$TEST_TMPDIR/test-log.json"

  init_log "myorg/myrepo" "$log_path"

  local content=$(cat "$log_path")
  local repo=$(json_get "$content" '.metadata.repo')
  [ "$repo" = "myorg/myrepo" ]
}

@test "init_log initializes empty stories object" {
  local log_path="$TEST_TMPDIR/test-log.json"

  init_log "test/repo" "$log_path"

  local content=$(cat "$log_path")
  local stories=$(json_get "$content" '.stories')
  [ "$stories" = "{}" ]
}

# =============================================================================
# LOG FILE OPERATIONS TESTS
# =============================================================================

@test "load_log reads valid log file" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local content=$(load_log "$TEST_TMPDIR/sample-log.json")
  assert_valid_json "$content"
}

@test "load_log fails for missing file" {
  run load_log "$TEST_TMPDIR/nonexistent.json"
  [ "$status" -ne 0 ]
}

@test "load_log fails for invalid JSON" {
  local log_path="$TEST_TMPDIR/invalid-log.json"
  echo "invalid json" > "$log_path"

  run load_log "$log_path"
  [ "$status" -ne 0 ]
}

@test "save_log writes valid JSON" {
  local log_path="$TEST_TMPDIR/test-log.json"
  local json='{"version": "1.0", "stories": {}}'

  save_log "$log_path" "$json"

  [ -f "$log_path" ]
  local content=$(cat "$log_path")
  assert_valid_json "$content"
}

@test "save_log prettifies JSON" {
  local log_path="$TEST_TMPDIR/test-log.json"
  local json='{"a":"b"}'

  save_log "$log_path" "$json"

  local content=$(cat "$log_path")
  # Prettified JSON will have newlines
  [[ "$content" == *$'\n'* ]]
}

# =============================================================================
# STORY OPERATIONS TESTS
# =============================================================================

@test "add_story_to_log adds new story" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local issue_json='{"number": 123, "title": "Test issue", "body": "Test body"}'
  add_story_to_log "$log_path" "123" "$issue_json"

  local content=$(load_log "$log_path")
  local story=$(json_get "$content" '.stories."GH-123"')

  assert_valid_json "$story"
  [ "$(json_get "$story" '.number')" = "123" ]
  [ "$(json_get "$story" '.title')" = "Test issue" ]
}

@test "add_story_to_log sets status to new" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local issue_json='{"number": 123, "title": "Test", "body": ""}'
  add_story_to_log "$log_path" "123" "$issue_json"

  local content=$(load_log "$log_path")
  local status=$(json_get "$content" '.stories."GH-123".refinement_status')

  [ "$status" = "new" ]
}

@test "story_by_number retrieves story" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local story=$(story_by_number "$TEST_TMPDIR/sample-log.json" "123")
  local title=$(json_get "$story" '.title')

  [ "$title" = "User authentication overhaul" ]
}

@test "story_by_number returns null for missing story" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local story=$(story_by_number "$TEST_TMPDIR/sample-log.json" "999")

  [ "$story" = "null" ]
}

@test "get_all_stories returns array" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local stories=$(get_all_stories "$TEST_TMPDIR/sample-log.json")
  local count=$(echo "$stories" | jq 'length')

  [ "$count" -eq 2 ]
}

# =============================================================================
# REFINEMENT UPDATE TESTS
# =============================================================================

@test "update_story_refinement changes status to dev-ready" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local app_state='{"timestamp": "2026-03-05T11:00:00Z"}'
  update_story_refinement "$TEST_TMPDIR/sample-log.json" "124" "Updated body" "$app_state"

  local content=$(load_log "$TEST_TMPDIR/sample-log.json")
  local status=$(json_get "$content" '.stories."GH-124".refinement_status')

  [ "$status" = "dev-ready" ]
}

@test "update_story_refinement sets last_refined timestamp" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local app_state='{"timestamp": "2026-03-05T11:00:00Z"}'
  update_story_refinement "$TEST_TMPDIR/sample-log.json" "124" "Updated body" "$app_state"

  local content=$(load_log "$TEST_TMPDIR/sample-log.json")
  local timestamp=$(json_get "$content" '.stories."GH-124".last_refined')

  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# =============================================================================
# APP STATE MANAGEMENT TESTS
# =============================================================================

@test "update_app_state_in_log updates app_state field" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local app_state='{"timestamp": "2026-03-05T12:00:00Z", "git_sha": "xyz789", "deployed_version": "1.3.0"}'
  update_app_state_in_log "$TEST_TMPDIR/sample-log.json" "$app_state"

  local content=$(load_log "$TEST_TMPDIR/sample-log.json")
  local version=$(json_get "$content" '.app_state.deployed_version')

  [ "$version" = "1.3.0" ]
}

@test "update_app_state_in_log updates last_check metadata" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local app_state='{}'
  update_app_state_in_log "$TEST_TMPDIR/sample-log.json" "$app_state"

  local content=$(load_log "$TEST_TMPDIR/sample-log.json")
  local last_check=$(json_get "$content" '.metadata.last_check')

  [[ "$last_check" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# =============================================================================
# FILTER TESTS
# =============================================================================

@test "get_needs_refinement_stories filters correctly" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  # Add a story with needs-refinement status
  local content=$(load_log "$log_path")
  content=$(echo "$content" | jq '.stories["GH-100"] = {
    number: 100,
    refinement_status: "needs-refinement",
    refinement_reasons: [],
    last_refined: null
  }')
  save_log "$log_path" "$content"

  local needs=$(get_needs_refinement_stories "$log_path")
  local count=$(echo "$needs" | jq 'length')

  [ "$count" -eq 1 ]
  [ "$(echo "$needs" | jq -r '.[0].refinement_status')" = "needs-refinement" ]
}

@test "get_needs_refinement_stories returns empty array when none" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local needs=$(get_needs_refinement_stories "$log_path")

  [ "$needs" = "[]" ]
}
