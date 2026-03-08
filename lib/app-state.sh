#!/bin/bash
# Application state capture and management

set -euo pipefail

# Guard against re-sourcing
[[ -n "${_REFINE_APP_STATE_LOADED:-}" ]] && return 0
_REFINE_APP_STATE_LOADED=1

# Source libraries (guard against re-sourcing)
[[ -z "${_REFINE_COMMON_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
[[ -z "${_REFINE_GITHUB_API_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/github-api.sh"

# =============================================================================
# GIT FUNCTIONS
# =============================================================================

get_git_sha() {
  local repo_root="$1"
  if [[ -d "$repo_root/.git" ]]; then
    cd "$repo_root"
    git rev-parse --short HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

get_git_branch() {
  local repo_root="$1"
  if [[ -d "$repo_root/.git" ]]; then
    cd "$repo_root"
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

# =============================================================================
# RECENT ACTIVITY
# =============================================================================

get_recent_closed_stories() {
  local repo="$1"
  local days="${2:-7}"

  # Calculate cutoff date (ISO 8601)
  local cutoff_date
  if [[ "$(uname)" == "Darwin" ]]; then
    cutoff_date=$(date -u -v-"${days}"d "+%Y-%m-%dT%H:%M:%SZ")
  else
    cutoff_date=$(date -u -d "$days days ago" "+%Y-%m-%dT%H:%M:%SZ")
  fi

  local endpoint="/repos/$repo/issues?state=closed&since=$cutoff_date&per_page=100"

  local page=1
  local closed_issues="[]"

  while true; do
    local page_endpoint="${endpoint}&page=$page"
    local response
    response=$(_github_api_call "GET" "$page_endpoint") || return 1

    if [[ -z "$response" || "$response" == "[]" ]]; then
      break
    fi

    # Compact JSON before passing to jq to avoid newline issues
    local response_compact
    response_compact=$(echo "$response" | jq -c '.')
    closed_issues=$(jq -n --argjson prev "$closed_issues" --argjson new "$response_compact" '$prev + $new')
    ((page++))
  done

  # Extract issue numbers and format as GH-NNN, return as compact JSON array
  echo "$closed_issues" | jq -c '[.[] | "GH-\(.number)"]' 2>/dev/null || echo "[]"
}

get_recent_modified_adr_files() {
  local repo_root="$1"
  local days="${2:-7}"

  if ! command -v find &> /dev/null; then
    return 0
  fi

  # Look for ADR files modified in last N days
  local adr_patterns=(
    "docs/adr/ADR-*.md"
    "adr/*.md"
    "docs/ADR-*.md"
  )

  local cutoff_time
  if [[ "$(uname)" == "Darwin" ]]; then
    cutoff_time=$(date -j -v-"${days}"d "+%Y%m%d%H%M%S")
  else
    cutoff_time=$(date -d "$days days ago" "+%Y%m%d%H%M%S")
  fi

  local found_files=()

  for pattern in "${adr_patterns[@]}"; do
    local full_pattern="$repo_root/$pattern"
    while IFS= read -r file; do
      if [[ -f "$file" ]]; then
        found_files+=("$file")
      fi
    done < <(find "$repo_root" -path "*adr*" -name "ADR-*.md" 2>/dev/null || echo "")
  done

  # Return unique files as compact JSON array
  printf '%s\n' "${found_files[@]}" | sort -u | jq -R '.' | jq -s -c '.'
}

# =============================================================================
# APP STATE SNAPSHOT
# =============================================================================

capture_app_state() {
  local repo_root="$1"
  local repo
  repo=$(github_repo)

  log_debug "Capturing app state from $repo_root"

  local timestamp
  timestamp=$(current_iso_time)

  local git_sha
  git_sha=$(get_git_sha "$repo_root")

  local git_branch
  git_branch=$(get_git_branch "$repo_root")

  local deployed_version
  deployed_version=$(get_deployed_version "$repo_root")

  local recent_closed
  recent_closed=$(get_recent_closed_stories "$repo" 7 2>/dev/null || echo "[]")

  local recent_adr_files
  recent_adr_files=$(get_recent_modified_adr_files "$repo_root" 7 2>/dev/null || echo "[]")

  # Variables are now already compact JSON arrays
  # Build JSON object
  jq -n \
    --arg timestamp "$timestamp" \
    --arg git_sha "$git_sha" \
    --arg git_branch "$git_branch" \
    --arg deployed_version "$deployed_version" \
    --argjson completed_stories "$recent_closed" \
    --argjson recent_adrs "$recent_adr_files" \
    '{
      timestamp: $timestamp,
      git_sha: $git_sha,
      git_branch: $git_branch,
      deployed_version: $deployed_version,
      completed_stories: $completed_stories,
      recent_adrs: $recent_adrs
    }'
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f get_git_sha get_git_branch
export -f get_recent_closed_stories get_recent_modified_adr_files
export -f capture_app_state
