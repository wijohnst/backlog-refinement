#!/bin/bash
# Backlog analysis - identify stories needing refinement

set -euo pipefail

# Guard against re-sourcing
[[ -n "${_REFINE_BACKLOG_ANALYSIS_LOADED:-}" ]] && return 0
_REFINE_BACKLOG_ANALYSIS_LOADED=1

# Source libraries
[[ -z "${_REFINE_COMMON_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
[[ -z "${_REFINE_GITHUB_API_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/github-api.sh"
[[ -z "${_REFINE_LOG_MANAGEMENT_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log-management.sh"

# =============================================================================
# REFINEMENT DETECTION
# =============================================================================

reasons_for_story() {
  local issue_json="$1"
  local log_entry_json="${2:-null}"

  local reasons="[]"
  local issue_number
  issue_number=$(echo "$issue_json" | jq -r '.number')

  # Reason 1: Has needs-refinement label
  local has_refinement_label
  has_refinement_label=$(echo "$issue_json" | jq '.labels[] | select(.name == "needs-refinement")' | jq -s 'length > 0')
  if [[ "$has_refinement_label" == "true" ]]; then
    reasons=$(echo "$reasons" | jq \
      '. += [{
        type: "label",
        value: "needs-refinement",
        detected_at: now | floor | tostring
      }]')
  fi

  # Reason 2: Story is old (>28 days) and hasn't been refined or needs re-refinement
  local created_at
  created_at=$(echo "$issue_json" | jq -r '.created_at')
  local days_old
  days_old=$(days_since "$created_at" || echo "999")

  if [[ $days_old -gt 28 ]]; then
    if [[ "$log_entry_json" == "null" ]]; then
      reasons=$(echo "$reasons" | jq \
        --arg days "$days_old" \
        '. += [{
          type: "age",
          value: ($days | tonumber),
          details: "Open for more than 28 days without refinement",
          detected_at: now | floor | tostring
        }]')
    fi
  fi

  # Reason 3: Body has changed since last refinement
  if [[ "$log_entry_json" != "null" ]]; then
    local last_body_hash
    last_body_hash=$(echo "$log_entry_json" | jq -r '.body_hash // empty')
    if [[ -n "$last_body_hash" ]]; then
      local current_body
      current_body=$(echo "$issue_json" | jq -r '.body // ""')
      local current_hash
      current_hash=$(hash_string "$current_body")

      if [[ "$current_hash" != "$last_body_hash" ]]; then
        reasons=$(echo "$reasons" | jq \
          '. += [{
            type: "body_changed",
            value: "Issue body has been modified",
            detected_at: now | floor | tostring
          }]')
      fi
    fi
  fi

  # Reason 4: Blocking dependency was merged
  if [[ "$log_entry_json" != "null" ]]; then
    local blocked_by
    blocked_by=$(echo "$log_entry_json" | jq '.dependencies.blocked_by // []')

    if [[ "$blocked_by" != "[]" ]]; then
      # Check each blocker - if it's closed, this should be re-refined
      # (Simplified: we'd need to call GitHub for each, so we flag it)
      local has_closed_blocker=0
      local blockers_to_check
      blockers_to_check=$(echo "$blocked_by" | jq -r '.[]')

      while IFS= read -r blocker_num; do
        # In a full implementation, would check if issue $blocker_num is closed
        # For now, flag as potential
        has_closed_blocker=1
        break
      done <<< "$blockers_to_check"

      if [[ $has_closed_blocker -eq 1 ]]; then
        reasons=$(echo "$reasons" | jq \
          '. += [{
            type: "blocker_merged",
            value: "Blocking dependency may have been resolved",
            detected_at: now | floor | tostring
          }]')
      fi
    fi
  fi

  echo "$reasons"
}

# =============================================================================
# BACKLOG ANALYSIS
# =============================================================================

analyze_backlog() {
  local repo="$1"
  local log_path="$2"

  log_debug "Analyzing backlog for $repo"

  # Get all open issues
  local all_issues
  all_issues=$(github_get_issues "$repo") || return 1

  # Get current log
  local log
  log=$(load_log "$log_path") || return 1

  # Process all issues with jq to avoid subshell issues
  local analysis_data
  analysis_data=$(echo "$all_issues" | jq -c '.[] | {
    number,
    title,
    issue_json: .
  }' | while IFS= read -r item; do
    local issue_number
    issue_number=$(echo "$item" | jq -r '.number')
    local issue_json
    issue_json=$(echo "$item" | jq -r '.issue_json')

    local log_entry
    log_entry=$(story_by_number "$log_path" "$issue_number")

    local reasons
    reasons=$(reasons_for_story "$issue_json" "$log_entry")

    # Compact JSON to avoid jq --argjson issues with newlines
    local reasons_compact
    reasons_compact=$(echo "$reasons" | jq -c '.')

    # Determine status
    if [[ "$log_entry" == "null" ]]; then
      echo "$item" | jq --argjson reasons "$reasons_compact" '. + {reasons: $reasons, status: "new"}'
    elif [[ "$reasons" != "[]" ]]; then
      echo "$item" | jq --argjson reasons "$reasons_compact" '. + {reasons: $reasons, status: "needs-refinement"}'
    else
      echo "$item" | jq '. + {status: "dev-ready"}'
    fi
  done | jq -s '.')

  # Separate by status
  local needs_refinement
  needs_refinement=$(echo "$analysis_data" | jq -c '[.[] | select(.status == "needs-refinement")]')
  local dev_ready
  dev_ready=$(echo "$analysis_data" | jq -c '[.[] | select(.status == "dev-ready")]')
  local new_stories
  new_stories=$(echo "$analysis_data" | jq -c '[.[] | select(.status == "new")]')

  # Return aggregated results
  jq -n \
    --argjson needs_refinement "$needs_refinement" \
    --argjson dev_ready "$dev_ready" \
    --argjson new_stories "$new_stories" \
    '{
      needs_refinement: $needs_refinement,
      dev_ready: $dev_ready,
      new_stories: $new_stories,
      summary: {
        total_needs_refinement: ($needs_refinement | length),
        total_dev_ready: ($dev_ready | length),
        total_new: ($new_stories | length)
      }
    }'
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f reasons_for_story analyze_backlog
