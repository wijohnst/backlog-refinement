#!/usr/bin/env bats
# Tests for lib/github-api.sh (with mocks)

setup() {
  load ../test_helper
  load_common
  load_mocks
  source "$REPO_DIR/lib/github-api.sh"
}

# =============================================================================
# TOKEN & REPO TESTS
# =============================================================================

@test "github_token returns mocked token" {
  result=$(github_token)
  [[ "$result" == *"test_token"* ]]
}

@test "github_repo returns test repo" {
  result=$(github_repo)
  [ "$result" = "test/repo" ]
}

# =============================================================================
# ISSUE FETCHING TESTS
# =============================================================================

@test "github_get_issues returns array" {
  local issues=$(github_get_issues "test/repo")

  assert_valid_json "$issues"
  [ "$(echo "$issues" | jq 'type')" = '"array"' ]
}

@test "github_get_issues returns mock issues" {
  local issues=$(github_get_issues "test/repo")

  local count=$(echo "$issues" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "github_get_issues returns issues with required fields" {
  local issues=$(github_get_issues "test/repo")

  local first=$(echo "$issues" | jq '.[0]')
  assert_json_has_key "$first" "number"
  assert_json_has_key "$first" "title"
  assert_json_has_key "$first" "body"
  assert_json_has_key "$first" "state"
  assert_json_has_key "$first" "labels"
}

@test "github_get_issue returns single issue" {
  local issue=$(github_get_issue "test/repo" 123)

  assert_valid_json "$issue"
  [ "$(json_get "$issue" '.number')" = "123" ]
}

@test "github_get_issue returns issue with correct title" {
  local issue=$(github_get_issue "test/repo" 123)

  [ "$(json_get "$issue" '.title')" = "User authentication overhaul" ]
}

# =============================================================================
# VERSION DETECTION TESTS
# =============================================================================

@test "get_deployed_version returns version" {
  result=$(get_deployed_version ".")

  [ "$result" = "1.2.3" ]
}

# =============================================================================
# ISSUE LINKS TESTS
# =============================================================================

@test "github_get_issue_links returns structured response" {
  local links=$(github_get_issue_links "test/repo" 123)

  assert_valid_json "$links"
  assert_json_has_key "$links" "blocks"
  assert_json_has_key "$links" "blocked_by"
  assert_json_has_key "$links" "relates_to"
}

@test "github_get_issue_links returns arrays" {
  local links=$(github_get_issue_links "test/repo" 123)

  [ "$(json_get "$links" '.blocks | type')" = '"array"' ]
  [ "$(json_get "$links" '.blocked_by | type')" = '"array"' ]
  [ "$(json_get "$links" '.relates_to | type')" = '"array"' ]
}

# =============================================================================
# UPDATE OPERATIONS TESTS
# =============================================================================

@test "github_update_issue accepts body string" {
  # Should not error with valid input
  run github_update_issue "test/repo" 123 "Updated body"
  # Mock just echoes, so won't fail
  [ "$status" -eq 0 ]
}

@test "github_add_label accepts label string" {
  # Should not error with valid input
  run github_add_label "test/repo" 123 "test-label"
  [ "$status" -eq 0 ]
}

@test "github_remove_label accepts label string" {
  # Should not error with valid input
  run github_remove_label "test/repo" 123 "test-label"
  [ "$status" -eq 0 ]
}

# =============================================================================
# COMMENT OPERATIONS TESTS
# =============================================================================

@test "github_add_comment accepts comment body" {
  run github_add_comment "test/repo" 123 "Test comment"
  [ "$status" -eq 0 ]
}
