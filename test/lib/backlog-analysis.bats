#!/usr/bin/env bats
# Tests for lib/backlog-analysis.sh

setup() {
  load ../test_helper
  load_common
  load_mocks
  source "$REFINE_BACKLOG_DIR/lib/log-management.sh"
  source "$REFINE_BACKLOG_DIR/lib/backlog-analysis.sh"
  setup_test_env
}

teardown() {
  teardown_test_env
}

# =============================================================================
# REASON DETECTION TESTS
# =============================================================================

@test "reasons_for_story detects needs-refinement label" {
  local issue_json='{
    "number": 123,
    "title": "Test",
    "labels": [{"name": "needs-refinement"}]
  }'

  local reasons=$(reasons_for_story "$issue_json" "null")

  # Should contain at least one reason
  [ "$(echo "$reasons" | jq 'length')" -gt 0 ]
  # Should have type "label"
  [[ "$(echo "$reasons" | jq -r '.[0].type')" == "label" ]]
}

@test "reasons_for_story detects old stories" {
  # Create an issue that's 30 days old
  local old_date
  if [[ "$(uname)" == "Darwin" ]]; then
    old_date=$(date -u -v-30d "+%Y-%m-%dT%H:%M:%SZ")
  else
    old_date=$(date -u -d "30 days ago" "+%Y-%m-%dT%H:%M:%SZ")
  fi

  local issue_json="{
    \"number\": 123,
    \"title\": \"Test\",
    \"created_at\": \"$old_date\",
    \"labels\": []
  }"

  local reasons=$(reasons_for_story "$issue_json" "null")

  # Should have age reason for old story without refinement
  # (This requires log_entry to be null to trigger the age check)
  local count=$(echo "$reasons" | jq 'length')
  [ "$count" -gt 0 ]
}

@test "reasons_for_story detects body changes" {
  local old_body="Old body content"
  local new_body="New body content"

  local old_hash=$(echo -n "$old_body" | sha256sum | cut -d' ' -f1)
  local new_hash=$(echo -n "$new_body" | sha256sum | cut -d' ' -f1)

  local issue_json="{
    \"number\": 123,
    \"title\": \"Test\",
    \"body\": \"$new_body\",
    \"labels\": []
  }"

  local log_entry="{
    \"body_hash\": \"$old_hash\"
  }"

  local reasons=$(reasons_for_story "$issue_json" "$log_entry")

  # Should detect body change
  [[ "$(echo "$reasons" | jq -r '.[].type')" == *"body_changed"* ]]
}

@test "reasons_for_story returns empty for unchanged story" {
  local body="Test body"
  local body_hash=$(echo -n "$body" | sha256sum | cut -d' ' -f1)

  local issue_json="{
    \"number\": 123,
    \"title\": \"Test\",
    \"body\": \"$body\",
    \"labels\": [],
    \"created_at\": \"2026-03-05T10:00:00Z\"
  }"

  local log_entry="{
    \"body_hash\": \"$body_hash\",
    \"dependencies\": {\"blocked_by\": []}
  }"

  local reasons=$(reasons_for_story "$issue_json" "$log_entry")

  # Unchanged story should have no reasons
  [ "$(echo "$reasons" | jq 'length')" -eq 0 ]
}

# =============================================================================
# BACKLOG ANALYSIS TESTS
# =============================================================================

@test "analyze_backlog returns valid JSON structure" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  assert_valid_json "$analysis"
  assert_json_has_key "$analysis" "needs_refinement"
  assert_json_has_key "$analysis" "dev_ready"
  assert_json_has_key "$analysis" "new_stories"
  assert_json_has_key "$analysis" "summary"
}

@test "analyze_backlog identifies new stories" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  local new_count=$(json_get "$analysis" '.summary.total_new')
  # Mock returns 2 issues, log is empty, so 2 should be new
  [ "$new_count" -eq 2 ]
}

@test "analyze_backlog counts stories correctly" {
  local log_path="$TEST_TMPDIR/test-log.json"
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local analysis=$(analyze_backlog "test/repo" "$TEST_TMPDIR/sample-log.json")

  local summary=$(json_get "$analysis" '.summary')
  local total=$(echo "$summary" | jq '.total_needs_refinement + .total_dev_ready + .total_new')

  # Should have at least the issues from the mock
  [ "$total" -ge 2 ]
}

@test "analyze_backlog handles empty backlog" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  local total=$(json_get "$analysis" '.summary.total_needs_refinement + .summary.total_dev_ready + .summary.total_new')

  # Mock returns 2 issues, log is empty, so all 2 are new
  [ "$total" -eq 2 ]
}

# =============================================================================
# STATUS CATEGORIZATION TESTS
# =============================================================================

@test "analyze_backlog categorizes stories into needs_refinement" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  # Mock issue 123 has needs-refinement label, so should be in needs_refinement
  local needs=$(json_get "$analysis" '.needs_refinement')
  local issue_123=$(echo "$needs" | jq '.[] | select(.number == 123)')

  [ -n "$issue_123" ]
}

@test "analyze_backlog categorizes new stories" {
  local log_path="$TEST_TMPDIR/test-log.json"
  init_log "test/repo" "$log_path"

  local analysis=$(analyze_backlog "test/repo" "$log_path")

  local new=$(json_get "$analysis" '.new_stories')
  local count=$(echo "$new" | jq 'length')

  # Both mock issues should be new (not in log)
  [ "$count" -eq 2 ]
}
