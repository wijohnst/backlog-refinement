#!/bin/bash
# Test helper functions for bats

# Get absolute paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
# Project root is now at REPO_DIR (lib/, scripts/, bin/ are at root level)

# Ensure we're in the repo directory for relative paths to work
cd "$REPO_DIR" || exit 1

# Create temporary test directory
setup_test_env() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  cd "$TEST_TMPDIR" || exit 1
}

# Clean up temporary test directory
teardown_test_env() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Initialize git repo for testing
init_test_git_repo() {
  git init > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git remote add origin "https://github.com/test/repo.git"
}

# Copy fixtures to test directory
copy_fixture() {
  local fixture_name="$1"
  local dest="${2:-.}"

  if [[ ! -f "$TEST_DIR/fixtures/$fixture_name" ]]; then
    echo "Fixture not found: $fixture_name"
    return 1
  fi

  cp "$TEST_DIR/fixtures/$fixture_name" "$dest/"
}

# Load mock functions
load_mocks() {
  source "$TEST_DIR/mocks/mock-github-api.sh"
}

# Load common.sh from repo
load_common() {
  source "$REPO_DIR/lib/common.sh"
}

# Load all libraries
load_libs() {
  load_common
  source "$REPO_DIR/lib/github-api.sh"
  source "$REPO_DIR/lib/app-state.sh"
  source "$REPO_DIR/lib/log-management.sh"
  source "$REPO_DIR/lib/backlog-analysis.sh"
  source "$REPO_DIR/lib/context-gathering.sh"
}

# Assert that a function exists and is callable
assert_function_exists() {
  local func_name="$1"

  if ! declare -f "$func_name" > /dev/null; then
    echo "Function not found: $func_name"
    return 1
  fi
}

# Assert JSON is valid
assert_valid_json() {
  local json="$1"

  if ! echo "$json" | jq empty 2>/dev/null; then
    echo "Invalid JSON: $json"
    return 1
  fi
}

# Assert JSON contains a specific key
assert_json_has_key() {
  local json="$1"
  local key="$2"

  if ! echo "$json" | jq "has(\"$key\")" 2>/dev/null | grep -q "true"; then
    echo "JSON missing key '$key': $json"
    return 1
  fi
}

# Get JSON value
json_get() {
  local json="$1"
  local path="$2"

  echo "$json" | jq -r "$path" 2>/dev/null
}

export -f setup_test_env teardown_test_env init_test_git_repo copy_fixture
export -f load_mocks load_common load_libs
export -f assert_function_exists assert_valid_json assert_json_has_key json_get
export TEST_DIR REPO_DIR
