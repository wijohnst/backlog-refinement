#!/bin/bash
# Context gathering for refinement calls

set -euo pipefail

# Guard against re-sourcing
[[ -n "${_REFINE_CONTEXT_GATHERING_LOADED:-}" ]] && return 0
_REFINE_CONTEXT_GATHERING_LOADED=1

# Source libraries
[[ -z "${_REFINE_COMMON_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
[[ -z "${_REFINE_GITHUB_API_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/github-api.sh"
[[ -z "${_REFINE_LOG_MANAGEMENT_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log-management.sh"

# =============================================================================
# FILE DISCOVERY
# =============================================================================

find_adr_files() {
  local repo_root="$1"
  local story_body="${2:-}"

  # Collect all ADR files in an array
  local files=()

  # Look for explicit ADR references in story body (e.g., "ADR-002.md" or "adr-002")
  if [[ -n "$story_body" ]]; then
    # Extract referenced ADRs
    local refs
    refs=$(echo "$story_body" | grep -oE "(ADR-[0-9]+|adr-[0-9]+)" | sort -u || true)

    while IFS= read -r ref; do
      if [[ -n "$ref" ]]; then
        # Search common ADR locations
        local adr_patterns=(
          "$repo_root/docs/adr/ADR-*.md"
          "$repo_root/adr/ADR-*.md"
          "$repo_root/docs/ADR-*.md"
          "$repo_root/ADR*.md"
        )

        for pattern_path in "${adr_patterns[@]}"; do
          local dir
          dir=$(dirname "$pattern_path")
          if [[ -d "$dir" ]]; then
            local found_file
            found_file=$(find "$dir" -iname "*${ref}*" -type f 2>/dev/null | head -1 || true)
            if [[ -n "$found_file" ]]; then
              files+=("$found_file")
              break
            fi
          fi
        done
      fi
    done <<< "$refs"
  fi

  # Also scan for all ADRs in known locations (up to 10)
  if [[ -d "$repo_root/docs/adr" ]]; then
    while IFS= read -r file; do
      if [[ -f "$file" ]]; then
        files+=("$file")
      fi
    done < <(find "$repo_root/docs/adr" -name "ADR-*.md" -type f 2>/dev/null | head -10)
  fi

  # Convert to JSON array with unique values
  printf '%s\n' "${files[@]}" | sort -u | jq -R '.' | jq -s '.'
}

find_plan_files() {
  local repo_root="$1"
  local story_keywords="${2:-}"

  local files=()

  # Look for plan files by convention (planning/*-plan.md)
  local plan_patterns=(
    "$repo_root/planning"
    "$repo_root/docs/planning"
    "$repo_root/plans"
  )

  for dir in "${plan_patterns[@]}"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r file; do
        if [[ -f "$file" ]]; then
          files+=("$file")
        fi
      done < <(find "$dir" -name "*-plan.md" -type f 2>/dev/null | head -20)
    fi
  done

  # Remove duplicates, limit to 10, and convert to JSON array
  printf '%s\n' "${files[@]}" | sort -u | head -10 | jq -R '.' | jq -s '.'
}

# =============================================================================
# FILE READING
# =============================================================================

read_file_safe() {
  local file="$1"
  local max_size_kb="${2:-100}"

  if [[ ! -f "$file" ]]; then
    echo ""
    return 1
  fi

  local file_size_kb
  file_size_kb=$(stat -f%z "$file" 2>/dev/null | awk '{printf "%.0f", $1/1024}' || stat -c%s "$file" 2>/dev/null | awk '{printf "%.0f", $1/1024}' || echo "999999")

  if [[ $file_size_kb -gt $max_size_kb ]]; then
    log_warn "File too large (${file_size_kb}KB > ${max_size_kb}KB), truncating: $file"
    head -c "$((max_size_kb * 1024))" "$file"
    echo ""
    echo "... (truncated)"
  else
    cat "$file"
  fi
}

# =============================================================================
# CONTEXT ASSEMBLY
# =============================================================================

gather_context() {
  local repo="$1"
  local story_numbers_str="$2"  # comma-separated: "123,124,125"
  local log_path="$3"
  local repo_root="$4"

  log_debug "Gathering context for stories: $story_numbers_str"

  local stories_json="[]"

  # Split story numbers
  IFS=',' read -ra story_numbers <<< "$story_numbers_str"

  for story_num in "${story_numbers[@]}"; do
    story_num=${story_num// /}  # Remove whitespace

    log_debug "Gathering context for story #$story_num"

    local issue
    issue=$(github_get_issue "$repo" "$story_num") || continue

    local issue_title
    issue_title=$(echo "$issue" | jq -r '.title')

    local issue_body
    issue_body=$(echo "$issue" | jq -r '.body // ""')

    # Find related ADRs
    local adr_files
    adr_files=$(find_adr_files "$repo_root" "$issue_body")

    # Build ADR context object
    local adr_context="{}"
    while IFS= read -r adr_file; do
      if [[ -n "$adr_file" && -f "$adr_file" ]]; then
        local adr_content
        adr_content=$(read_file_safe "$adr_file" 50)
        adr_context=$(echo "$adr_context" | jq \
          --arg file "$adr_file" \
          --arg content "$adr_content" \
          ".[\$file] = \$content")
      fi
    done < <(echo "$adr_files" | jq -r '.[]')

    # Find related plan files
    local plan_files
    plan_files=$(find_plan_files "$repo_root" "$issue_title")

    # Build plan context object
    local plan_context="{}"
    while IFS= read -r plan_file; do
      if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        local plan_content
        plan_content=$(read_file_safe "$plan_file" 50)
        plan_context=$(echo "$plan_context" | jq \
          --arg file "$plan_file" \
          --arg content "$plan_content" \
          ".[\$file] = \$content")
      fi
    done < <(echo "$plan_files" | jq -r '.[]')

    # Get related stories from log
    local related_stories="[]"
    local log_entry
    log_entry=$(story_by_number "$log_path" "$story_num")

    if [[ "$log_entry" != "null" ]]; then
      # Get blocked_by and relates_to
      local related_numbers
      related_numbers=$(echo "$log_entry" | jq '.dependencies | (.blocked_by // []) + (.relates_to // [])' | jq -r '.[]' 2>/dev/null || echo "")

      while IFS= read -r related_num; do
        if [[ -n "$related_num" ]]; then
          local related_issue
          related_issue=$(github_get_issue "$repo" "$related_num" 2>/dev/null || echo "null")

          if [[ "$related_issue" != "null" ]]; then
            related_stories=$(echo "$related_stories" | jq \
              --arg num "$related_num" \
              --arg title "$(echo "$related_issue" | jq -r '.title')" \
              --arg body "$(echo "$related_issue" | jq -r '.body // ""')" \
              --arg status "$(if echo "$related_issue" | jq -e '.closed_at' > /dev/null 2>&1; then echo "closed"; else echo "open"; fi)" \
              '. += [{
                number: ($num | tonumber),
                title: $title,
                body: $body,
                status: $status
              }]')
          fi
        fi
      done <<< "$related_numbers"
    fi

    # Get last refinement snapshot if available
    local last_refinement_snapshot="null"
    if [[ "$log_entry" != "null" ]]; then
      last_refinement_snapshot=$(echo "$log_entry" | jq '.last_refined_app_state // null')
    fi

    # Build story context
    local story_context
    # Compact JSON to single line to avoid jq --argjson issues
    local adr_context_compact
    adr_context_compact=$(echo "$adr_context" | jq -c '.')
    local plan_context_compact
    plan_context_compact=$(echo "$plan_context" | jq -c '.')
    local related_stories_compact
    related_stories_compact=$(echo "$related_stories" | jq -c '.')
    local last_refinement_snapshot_compact
    last_refinement_snapshot_compact=$(echo "$last_refinement_snapshot" | jq -c '.')

    story_context=$(jq -n \
      --arg num "$story_num" \
      --arg title "$issue_title" \
      --arg body "$issue_body" \
      --argjson adr_files "$adr_context_compact" \
      --argjson plan_files "$plan_context_compact" \
      --argjson related_stories "$related_stories_compact" \
      --argjson last_snapshot "$last_refinement_snapshot_compact" \
      '{
        number: ($num | tonumber),
        title: $title,
        current_body: $body,
        context: {
          adr_files: $adr_files,
          plan_files: $plan_files,
          related_stories: $related_stories
        },
        last_refinement_snapshot: $last_snapshot
      }')

    # Compact story_context before passing to jq --argjson
    local story_context_compact
    story_context_compact=$(echo "$story_context" | jq -c '.')
    stories_json=$(echo "$stories_json" | jq --argjson story "$story_context_compact" '. += [$story]')
  done

  # Return payload (compact JSON to avoid jq --argjson issues)
  local stories_json_compact
  stories_json_compact=$(echo "$stories_json" | jq -c '.')
  jq -n --argjson stories "$stories_json_compact" '{stories: $stories}'
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f find_adr_files find_plan_files read_file_safe gather_context
