#!/usr/bin/env bats
# Tests for lib/common.sh

setup() {
  load ../test_helper
  load_common
}

# =============================================================================
# LOGGING TESTS
# =============================================================================

@test "log_info outputs to stderr" {
  output=$(log_info "test message" 2>&1 >/dev/null)
  [[ "$output" == *"test message"* ]]
}

@test "log_error outputs to stderr" {
  output=$(log_error "error message" 2>&1 >/dev/null)
  [[ "$output" == *"error message"* ]]
}

@test "log_success outputs to stderr" {
  output=$(log_success "success message" 2>&1 >/dev/null)
  [[ "$output" == *"success message"* ]]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "require_command fails for missing command" {
  run require_command "nonexistent_command_xyz_123"
  [ "$status" -eq 1 ]
}

@test "require_command succeeds for existing command" {
  run require_command "bash"
  [ "$status" -eq 0 ]
}

@test "require_env fails for unset variable" {
  unset NONEXISTENT_VAR_XYZ
  run require_env "NONEXISTENT_VAR_XYZ"
  [ "$status" -eq 1 ]
}

@test "require_env succeeds for set variable" {
  export EXISTING_VAR="value"
  run require_env "EXISTING_VAR"
  [ "$status" -eq 0 ]
}

@test "fail exits with status 1" {
  run bash -c 'source refine-backlog/lib/common.sh; fail "test error"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"test error"* ]]
}

# =============================================================================
# JSON HELPER TESTS
# =============================================================================

@test "json_validate accepts valid JSON" {
  local json='{"key": "value"}'
  run json_validate "$json"
  [ "$status" -eq 0 ]
}

@test "json_validate rejects invalid JSON" {
  local json='invalid json'
  run json_validate "$json"
  [ "$status" -ne 0 ]
}

@test "jq_filter extracts value from JSON" {
  local json='{"name": "test", "value": 123}'
  result=$(jq_filter "$json" '.name')
  [ "$result" = "test" ]
}

@test "jq_filter returns empty for missing key" {
  local json='{"name": "test"}'
  result=$(jq_filter "$json" '.missing')
  # jq returns "null" for missing keys with -r flag, or empty string on error
  [[ "$result" == "null" || -z "$result" ]]
}

@test "json_to_var extracts value" {
  local json='{"repo": "test/repo", "version": "1.0"}'
  result=$(json_to_var "$json" "repo")
  [ "$result" = "test/repo" ]
}

# =============================================================================
# FILE UTILITY TESTS
# =============================================================================

@test "ensure_file creates file if missing" {
  setup_test_env
  local test_file="$TEST_TMPDIR/test.txt"

  ensure_file "$test_file"
  [ -f "$test_file" ]

  teardown_test_env
}

@test "ensure_file doesn't overwrite existing file" {
  setup_test_env
  local test_file="$TEST_TMPDIR/test.txt"

  echo "original" > "$test_file"
  ensure_file "$test_file"
  grep -q "original" "$test_file"

  teardown_test_env
}

@test "ensure_dir creates directory if missing" {
  setup_test_env
  local test_dir="$TEST_TMPDIR/subdir/nested"

  ensure_dir "$test_dir"
  [ -d "$test_dir" ]

  teardown_test_env
}

@test "file_hash returns consistent hash" {
  setup_test_env
  local test_file="$TEST_TMPDIR/test.txt"

  echo "content" > "$test_file"
  hash1=$(file_hash "$test_file")
  hash2=$(file_hash "$test_file")

  [ "$hash1" = "$hash2" ]
  [ ${#hash1} -eq 64 ]  # SHA256 hex is 64 chars

  teardown_test_env
}

@test "file_hash returns empty for missing file" {
  setup_test_env

  result=$(file_hash "$TEST_TMPDIR/nonexistent.txt" 2>/dev/null || true)
  [ -z "$result" ]

  teardown_test_env
}

# =============================================================================
# LOCKING TESTS
# =============================================================================

@test "acquire_lock creates lock file" {
  setup_test_env
  local lock_file="$TEST_TMPDIR/test.lock"

  acquire_lock "$lock_file" 1
  [ -f "$lock_file" ]

  release_lock "$lock_file"

  teardown_test_env
}

@test "release_lock removes lock file" {
  setup_test_env
  local lock_file="$TEST_TMPDIR/test.lock"

  acquire_lock "$lock_file" 1
  release_lock "$lock_file"

  [ ! -f "$lock_file" ]

  teardown_test_env
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "current_iso_time returns ISO format" {
  result=$(current_iso_time)

  # Check format: YYYY-MM-DDTHH:MM:SSZ
  [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "iso_to_epoch converts ISO date to seconds" {
  result=$(iso_to_epoch "2026-01-01T00:00:00Z")

  # Should be a number
  [[ "$result" =~ ^[0-9]+$ ]]
  # Should be greater than a recent timestamp
  [ "$result" -gt 1700000000 ]
}

@test "days_since calculates days correctly" {
  # Create a date 5 days ago
  local five_days_ago
  if [[ "$(uname)" == "Darwin" ]]; then
    five_days_ago=$(date -u -v-5d "+%Y-%m-%dT%H:%M:%SZ")
  else
    five_days_ago=$(date -u -d "5 days ago" "+%Y-%m-%dT%H:%M:%SZ")
  fi

  result=$(days_since "$five_days_ago")

  # Should be approximately 5 (allow 1 day variance due to time differences)
  [ "$result" -ge 4 ]
  [ "$result" -le 6 ]
}

# =============================================================================
# CONFIG TESTS
# =============================================================================

@test "github_token returns env var when set" {
  export GITHUB_TOKEN="test_token_123"
  result=$(github_token)
  [ "$result" = "test_token_123" ]
  unset GITHUB_TOKEN
}

@test "github_repo extracts from git remote" {
  setup_test_env
  init_test_git_repo
  unset GITHUB_REPO  # Ensure fallback to git remote detection

  result=$(github_repo)
  [ "$result" = "test/repo" ]

  teardown_test_env
}

@test "log_level returns info by default" {
  unset LOG_LEVEL
  result=$(log_level)
  [ "$result" = "info" ]
}

@test "log_level returns set value" {
  export LOG_LEVEL="debug"
  result=$(log_level)
  [ "$result" = "debug" ]
  unset LOG_LEVEL
}
