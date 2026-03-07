#!/bin/bash
# Refinement log management (refinement-log.json)

set -euo pipefail

# Guard against re-sourcing
[[ -n "${_REFINE_LOG_MANAGEMENT_LOADED:-}" ]] && return 0
_REFINE_LOG_MANAGEMENT_LOADED=1

# Source common utilities
[[ -z "${_REFINE_COMMON_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# =============================================================================
# LOG INITIALIZATION
# =============================================================================

init_log() {
  local repo="$1"
  local log_path="$2"

  log_debug "Initializing refinement log at $log_path"

  local timestamp
  timestamp=$(current_iso_time)

  local log_json
  log_json=$(jq -n \
    --arg version "1.0" \
    --arg repo "$repo" \
    --arg timestamp "$timestamp" \
    '{
      version: $version,
      metadata: {
        repo: $repo,
        initialized_at: $timestamp,
        last_check: null,
        last_refinement: null
      },
      app_state: {},
      stories: {}
    }')

  save_log "$log_path" "$log_json"
  log_success "Initialized refinement log"
}

# =============================================================================
# LOG FILE OPERATIONS
# =============================================================================

load_log() {
  local log_path="$1"

  if [[ ! -f "$log_path" ]]; then
    log_error "Refinement log not found: $log_path"
    return 1
  fi

  local log_content
  log_content=$(cat "$log_path" 2>/dev/null || echo "{}")

  if ! json_validate "$log_content"; then
    log_error "Invalid JSON in refinement log: $log_path"
    return 1
  fi

  echo "$log_content"
}

save_log() {
  local log_path="$1"
  local json_data="$2"

  if ! json_validate "$json_data"; then
    fail "Invalid JSON data for refinement log"
  fi

  local temp_file
  temp_file=$(mktemp)

  # Pretty-print JSON and save to temp file
  echo "$json_data" | jq '.' > "$temp_file"

  # Atomic move
  mv "$temp_file" "$log_path"
  log_debug "Saved refinement log to $log_path"
}

# =============================================================================
# STORY OPERATIONS
# =============================================================================

add_story_to_log() {
  local log_path="$1"
  local story_number="$2"
  local issue_json="$3"

  local log
  log=$(load_log "$log_path") || return 1

  local body_hash
  local body_text
  body_text=$(echo "$issue_json" | jq -r '.body // ""')
  body_hash=$(hash_string "$body_text")

  local story_key="GH-$story_number"

  # Add story to log with "new" status
  log=$(echo "$log" | jq \
    --arg key "$story_key" \
    --arg number "$story_number" \
    --arg title "$(echo "$issue_json" | jq -r '.title')" \
    --arg body_hash "$body_hash" \
    '.stories[$key] = {
      number: $number | tonumber,
      title: $title,
      refinement_status: "new",
      refinement_reasons: [],
      last_refined: null,
      last_refined_app_state: null,
      body_hash: $body_hash,
      dependencies: {
        blocks: [],
        blocked_by: [],
        relates_to: []
      }
    }')

  save_log "$log_path" "$log"
  log_debug "Added story $story_key to log"
}

story_by_number() {
  local log_path="$1"
  local number="$2"

  local log
  log=$(load_log "$log_path") || return 1

  local story_key="GH-$number"

  echo "$log" | jq ".stories[\"$story_key\"] // null" 2>/dev/null || echo "null"
}

get_needs_refinement_stories() {
  local log_path="$1"

  local log
  log=$(load_log "$log_path") || return 1

  echo "$log" | jq '.stories | to_entries[] | select(.value.refinement_status == "needs-refinement") | .value' 2>/dev/null || echo "[]"
}

get_all_stories() {
  local log_path="$1"

  local log
  log=$(load_log "$log_path") || return 1

  echo "$log" | jq '.stories | to_entries[] | .value' 2>/dev/null || echo "[]"
}

# =============================================================================
# REFINEMENT UPDATES
# =============================================================================

update_story_refinement() {
  local log_path="$1"
  local story_number="$2"
  local refined_body="$3"
  local app_state_json="$4"

  local log
  log=$(load_log "$log_path") || return 1

  local story_key="GH-$story_number"
  local timestamp
  timestamp=$(current_iso_time)

  local body_hash
  body_hash=$(hash_string "$refined_body")

  # Update story with dev-ready status
  log=$(echo "$log" | jq \
    --arg key "$story_key" \
    --arg timestamp "$timestamp" \
    --arg body_hash "$body_hash" \
    --argjson app_state "$app_state_json" \
    '.stories[$key].refinement_status = "dev-ready" |
     .stories[$key].last_refined = $timestamp |
     .stories[$key].last_refined_app_state = $app_state |
     .stories[$key].body_hash = $body_hash')

  save_log "$log_path" "$log"
  log_debug "Updated refinement status for story $story_key"
}

# =============================================================================
# APP STATE MANAGEMENT
# =============================================================================

update_app_state_in_log() {
  local log_path="$1"
  local app_state_json="$2"

  local log
  log=$(load_log "$log_path") || return 1

  # Compact JSON to single line to avoid jq --argjson issues
  local app_state_compact
  app_state_compact=$(echo "$app_state_json" | jq -c '.')

  log=$(echo "$log" | jq \
    --argjson app_state "$app_state_compact" \
    '.app_state = $app_state')

  # Update last_check timestamp
  local timestamp
  timestamp=$(current_iso_time)
  log=$(echo "$log" | jq \
    --arg timestamp "$timestamp" \
    '.metadata.last_check = $timestamp')

  save_log "$log_path" "$log"
  log_debug "Updated app state in refinement log"
}

# =============================================================================
# METADATA MANAGEMENT
# =============================================================================

update_log_last_refinement() {
  local log_path="$1"

  local log
  log=$(load_log "$log_path") || return 1

  local timestamp
  timestamp=$(current_iso_time)

  log=$(echo "$log" | jq \
    --arg timestamp "$timestamp" \
    '.metadata.last_refinement = $timestamp')

  save_log "$log_path" "$log"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f init_log load_log save_log
export -f add_story_to_log story_by_number get_needs_refinement_stories get_all_stories
export -f update_story_refinement update_app_state_in_log update_log_last_refinement
