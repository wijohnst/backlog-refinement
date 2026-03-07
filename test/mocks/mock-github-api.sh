#!/bin/bash
# Mock GitHub API for testing (no associative arrays for sh compatibility)

# Mock github_token - returns a dummy token
github_token() {
  echo "ghp_test_token_1234567890"
}

# Mock github_repo - returns test repo
github_repo() {
  echo "test/repo"
}

# Mock _github_api_call with preset responses
_github_api_call() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  # Return mock response based on endpoint
  case "$endpoint" in
    "/repos/test/repo/issues?state=open&per_page=100&page=1")
      cat <<'EOF'
[
  {
    "number": 123,
    "title": "User authentication overhaul",
    "body": "# Overview\nWe need to update authentication\n\nblocks #124",
    "created_at": "2026-02-01T10:00:00Z",
    "state": "open",
    "labels": [{"name": "needs-refinement"}]
  },
  {
    "number": 124,
    "title": "Session management",
    "body": "Handle user sessions",
    "created_at": "2026-02-15T10:00:00Z",
    "state": "open",
    "labels": []
  }
]
EOF
      ;;
    "/repos/test/repo/issues/123")
      cat <<'EOF'
{
  "number": 123,
  "title": "User authentication overhaul",
  "body": "# Overview\nWe need to update authentication",
  "created_at": "2026-02-01T10:00:00Z",
  "state": "open",
  "labels": [{"name": "needs-refinement"}]
}
EOF
      ;;
    "/repos/test/repo/issues/124")
      cat <<'EOF'
{
  "number": 124,
  "title": "Session management",
  "body": "Handle user sessions",
  "created_at": "2026-02-15T10:00:00Z",
  "state": "open",
  "labels": []
}
EOF
      ;;
    *)
      echo "[]"
      ;;
  esac
}

# Mock get_deployed_version
get_deployed_version() {
  echo "1.2.3"
}

export -f github_token github_repo _github_api_call get_deployed_version
