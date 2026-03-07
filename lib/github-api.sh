#!/bin/bash
# GitHub REST API wrapper

set -euo pipefail

# Guard against re-sourcing
[[ -n "${_REFINE_GITHUB_API_LOADED:-}" ]] && return 0
_REFINE_GITHUB_API_LOADED=1

# Source common utilities
[[ -z "${_REFINE_COMMON_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# =============================================================================
# GITHUB API HELPERS
# =============================================================================

_github_api_call() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local token
  token=$(github_token)

  local url="https://api.github.com${endpoint}"
  local response_file
  response_file=$(mktemp)

  local http_code
  http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
    -X "$method" \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github.v3+json" \
    ${data:+-H "Content-Type: application/json" -d "$data"} \
    "$url" 2>/dev/null) || http_code="999"

  local response
  response=$(cat "$response_file" 2>/dev/null || echo "{}")
  rm -f "$response_file"

  # Handle rate limiting
  if [[ "$http_code" == "429" ]]; then
    log_warn "GitHub API rate limit exceeded. Waiting 60s before retry..."
    sleep 60
    # Recursive retry
    _github_api_call "$method" "$endpoint" "$data"
    return
  fi

  # Handle errors
  if [[ "$http_code" != "200" && "$http_code" != "201" && "$http_code" != "204" ]]; then
    log_error "GitHub API error (HTTP $http_code): $endpoint"
    log_debug "Response: $response"
    echo "{}" >&2
    return 1
  fi

  echo "$response"
}

# =============================================================================
# ISSUES
# =============================================================================

github_get_issues() {
  local repo="$1"
  local label_filter="${2:-}"

  local endpoint="/repos/$repo/issues?state=open&per_page=100"
  if [[ -n "$label_filter" ]]; then
    # URL-encode label name
    label_filter="${label_filter// /%20}"
    endpoint="$endpoint&labels=$label_filter"
  fi

  local page=1
  local all_issues="[]"

  while true; do
    local page_endpoint="${endpoint}&page=$page"
    local response
    response=$(_github_api_call "GET" "$page_endpoint") || return 1

    if [[ -z "$response" || "$response" == "[]" ]]; then
      break
    fi

    all_issues=$(jq -n --argjson prev "$all_issues" --argjson new "$response" '$prev + $new')
    ((page++))
  done

  echo "$all_issues"
}

github_get_issue() {
  local repo="$1"
  local number="$2"
  local endpoint="/repos/$repo/issues/$number"
  _github_api_call "GET" "$endpoint"
}

github_get_issue_links() {
  local repo="$1"
  local number="$2"
  local endpoint="/repos/$repo/issues/$number"

  local issue
  issue=$(_github_api_call "GET" "$endpoint") || return 1

  # Parse the issue body for GitHub issue links (blocks, blocked_by, relates_to)
  # This is a simple implementation that looks for patterns in the body
  local body
  body=$(echo "$issue" | jq -r '.body // empty' 2>/dev/null)

  local blocks="[]"
  local blocked_by="[]"
  local relates_to="[]"

  # Look for patterns like "blocks #123" or "blocked by #456"
  if [[ -n "$body" ]]; then
    # Extract numbers from blocks pattern
    blocks=$(echo "$body" | grep -oE "(blocks|closes|fixes)\s+#[0-9]+" | grep -oE "[0-9]+" | jq -R 'tonumber' | jq -s '.' 2>/dev/null || echo "[]")

    # Extract numbers from blocked_by pattern
    blocked_by=$(echo "$body" | grep -oE "(blocked\s+by|depends\s+on)\s+#[0-9]+" | grep -oE "[0-9]+" | jq -R 'tonumber' | jq -s '.' 2>/dev/null || echo "[]")

    # Extract numbers from relates_to pattern
    relates_to=$(echo "$body" | grep -oE "(relates\s+to|related\s+to)\s+#[0-9]+" | grep -oE "[0-9]+" | jq -R 'tonumber' | jq -s '.' 2>/dev/null || echo "[]")
  fi

  # Output as JSON object
  jq -n \
    --argjson blocks "$blocks" \
    --argjson blocked_by "$blocked_by" \
    --argjson relates_to "$relates_to" \
    '{blocks: $blocks, blocked_by: $blocked_by, relates_to: $relates_to}'
}

github_update_issue() {
  local repo="$1"
  local number="$2"
  local body="$3"

  local endpoint="/repos/$repo/issues/$number"
  local data
  data=$(jq -n --arg body "$body" '{body: $body}')

  _github_api_call "PATCH" "$endpoint" "$data"
}

# =============================================================================
# LABELS
# =============================================================================

github_add_label() {
  local repo="$1"
  local number="$2"
  local label="$3"

  local endpoint="/repos/$repo/issues/$number/labels"
  local data
  data=$(jq -n --arg label "$label" '{labels: [$label]}')

  _github_api_call "POST" "$endpoint" "$data" > /dev/null
}

github_remove_label() {
  local repo="$1"
  local number="$2"
  local label="$3"

  local endpoint="/repos/$repo/issues/$number/labels/$label"
  _github_api_call "DELETE" "$endpoint" > /dev/null
}

# =============================================================================
# COMMENTS
# =============================================================================

github_add_comment() {
  local repo="$1"
  local number="$2"
  local body="$3"

  local endpoint="/repos/$repo/issues/$number/comments"
  local data
  data=$(jq -n --arg body "$body" '{body: $body}')

  _github_api_call "POST" "$endpoint" "$data"
}

# =============================================================================
# VERSION DETECTION
# =============================================================================

get_deployed_version() {
  local repo_root="$1"

  # Try git tags first
  if command -v git &> /dev/null && [[ -d "$repo_root/.git" ]]; then
    local latest_tag
    latest_tag=$(cd "$repo_root" && git describe --tags 2>/dev/null | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+" || echo "")
    if [[ -n "$latest_tag" ]]; then
      echo "$latest_tag"
      return 0
    fi
  fi

  # Try package.json
  if [[ -f "$repo_root/package.json" ]]; then
    local version
    version=$(jq -r '.version // empty' "$repo_root/package.json" 2>/dev/null || echo "")
    if [[ -n "$version" ]]; then
      echo "$version"
      return 0
    fi
  fi

  # Try VERSION file
  if [[ -f "$repo_root/VERSION" ]]; then
    cat "$repo_root/VERSION"
    return 0
  fi

  echo "unknown"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f _github_api_call
export -f github_get_issues github_get_issue github_get_issue_links
export -f github_update_issue github_add_label github_remove_label
export -f github_add_comment get_deployed_version
