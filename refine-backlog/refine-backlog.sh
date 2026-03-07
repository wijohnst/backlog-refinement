#!/bin/bash
# Backlog Refinement System - Main CLI

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library modules
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/github-api.sh"
source "$SCRIPT_DIR/lib/app-state.sh"
source "$SCRIPT_DIR/lib/log-management.sh"
source "$SCRIPT_DIR/lib/backlog-analysis.sh"
source "$SCRIPT_DIR/lib/context-gathering.sh"

# Configuration
readonly LOG_FILE="${LOG_FILE:-.}/refinement-log.json"
readonly LOCK_FILE="${LOG_FILE}.lock"
readonly BATCH_SIZE="${BATCH_SIZE:-10}"

# =============================================================================
# HELP & VERSION
# =============================================================================

show_help() {
  cat <<'EOF'
Backlog Refinement System - GitHub issue refinement at scale

USAGE:
  refine-backlog <command> [options]

COMMANDS:
  init              Initialize refinement system in current repo
  check             Analyze backlog, identify stories needing refinement
  refine            Refine stories using Claude
  status            Show refinement status
  update-log        Capture and update app state snapshot

OPTIONS:
  --help            Show this help message
  --version         Show version
  --debug           Enable debug logging
  --dry-run         Preview without making changes (for 'refine')

EXAMPLES:
  # Initialize system
  refine-backlog init

  # Check what needs refinement
  refine-backlog check
  refine-backlog check --details
  refine-backlog check --json

  # Refine stories
  refine-backlog refine --all
  refine-backlog refine --ids GH-123,GH-124
  refine-backlog refine --all --dry-run
  refine-backlog refine --all --confirm

  # Status
  refine-backlog status
  refine-backlog status --story GH-123
  refine-backlog status --json

  # Update app state snapshot
  refine-backlog update-log

EOF
}

show_version() {
  echo "refine-backlog v1.0.0"
}

# =============================================================================
# API INTEGRATION
# =============================================================================

call_claude_api() {
  local system_prompt="$1"
  local user_prompt="$2"

  local api_key
  api_key=$(anthropic_api_key)

  log_debug "Calling Claude API (claude-opus-4-6)..."

  local response_file
  response_file=$(mktemp)

  local payload
  payload=$(jq -n \
    --arg model "claude-opus-4-6" \
    --arg system "$system_prompt" \
    --arg user "$user_prompt" \
    '{
      model: $model,
      max_tokens: 4096,
      system: $system,
      messages: [
        {
          role: "user",
          content: $user
        }
      ]
    }')

  local http_code
  http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -d "$payload" 2>/dev/null) || http_code="999"

  local response
  response=$(cat "$response_file" 2>/dev/null || echo "{}")
  rm -f "$response_file"

  if [[ "$http_code" != "200" ]]; then
    log_error "Claude API error (HTTP $http_code)"
    log_debug "Response: $response"
    fail "Failed to call Claude API"
  fi

  # Extract text from response
  echo "$response" | jq -r '.content[0].text // ""' 2>/dev/null || echo ""
}

# =============================================================================
# SUBCOMMANDS
# =============================================================================

cmd_init() {
  log_info "Initializing backlog refinement system..."

  # Check git repo
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    fail "Not a git repository"
  fi

  # Get repo name
  local repo
  repo=$(github_repo)

  log_info "Repository: $repo"

  # Check tokens
  if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    log_warn "Neither GITHUB_TOKEN nor ANTHROPIC_API_KEY env vars set"
    log_info "You will be prompted to set these in the config file"
  fi

  # Create config directory
  local config_dir="${HOME}/.local"
  ensure_dir "$config_dir"

  # Create config file if it doesn't exist
  local config_file="$config_dir/refine-backlog.conf"
  if [[ ! -f "$config_file" ]]; then
    cat > "$config_file" <<EOF
# Backlog Refinement System Configuration

# GitHub API token (required)
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Anthropic API key (required for refinement)
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# GitHub repository (auto-detected if in git repo)
GITHUB_REPO="$repo"

# Logging level: info, debug
LOG_LEVEL="info"

# ADR file patterns (space-separated)
ADR_PATTERNS=("docs/adr/ADR-*.md" "adr/*.md")

# Plan file patterns (space-separated)
PLAN_PATTERNS=("planning/*-plan.md" "docs/planning/*-plan.md")

# Days before a story is considered "stale" for refinement
MIN_DAYS_TO_REFINEMENT="28"

# Stories per Claude API call
BATCH_SIZE="10"
EOF
    log_success "Created config file: $config_file"
    log_info "Edit this file to add your API tokens"
  else
    log_info "Config file already exists: $config_file"
  fi

  # Initialize refinement log
  if [[ ! -f "$LOG_FILE" ]]; then
    init_log "$repo" "$LOG_FILE"
    log_success "Initialized refinement log: $LOG_FILE"
  else
    log_info "Refinement log already exists: $LOG_FILE"
  fi

  # Add to .gitignore
  if [[ -f .gitignore ]]; then
    if ! grep -q "refinement-log.json" .gitignore 2>/dev/null; then
      echo "refinement-log.json.lock" >> .gitignore
      log_success "Added lock file to .gitignore"
    fi
  fi

  log_success "Initialization complete!"
  log_info "Next: run 'refine-backlog check' to analyze your backlog"
}

cmd_check() {
  local details=0
  local json_output=0

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --details) details=1; shift ;;
      --json) json_output=1; shift ;;
      *) shift ;;
    esac
  done

  if [[ ! -f "$LOG_FILE" ]]; then
    fail "Refinement log not found. Run 'refine-backlog init' first"
  fi

  log_info "Analyzing backlog..."

  local repo
  repo=$(github_repo)

  # Capture current app state
  local app_state
  app_state=$(capture_app_state ".")
  update_app_state_in_log "$LOG_FILE" "$app_state"

  # Analyze backlog
  local analysis
  analysis=$(analyze_backlog "$repo" "$LOG_FILE") || fail "Failed to analyze backlog"

  if [[ $json_output -eq 1 ]]; then
    echo "$analysis"
  else
    # Human-readable output
    local needs_count
    needs_count=$(echo "$analysis" | jq '.summary.total_needs_refinement')
    local new_count
    new_count=$(echo "$analysis" | jq '.summary.total_new')
    local ready_count
    ready_count=$(echo "$analysis" | jq '.summary.total_dev_ready')

    log_success "Backlog analysis complete!"
    echo ""
    echo "Stories needing refinement: $needs_count"
    echo "New stories: $new_count"
    echo "Dev-ready stories: $ready_count"
    echo ""

    if [[ $details -eq 1 ]]; then
      echo "=== Needs Refinement ==="
      echo "$analysis" | jq -r '.needs_refinement[] | "  GH-\(.number): \(.title)"' || true
      echo ""

      echo "=== New Stories ==="
      echo "$analysis" | jq -r '.new_stories[] | "  GH-\(.number): \(.title)"' || true
      echo ""

      echo "=== Dev-Ready ==="
      echo "$analysis" | jq -r '.dev_ready[] | "  GH-\(.number): \(.title)"' || true
    fi
  fi
}

cmd_refine() {
  local refine_all=0
  local ids_str=""
  local dry_run=0
  local confirm=0

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) refine_all=1; shift ;;
      --ids) ids_str="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --confirm) confirm=1; shift ;;
      *) shift ;;
    esac
  done

  if [[ ! -f "$LOG_FILE" ]]; then
    fail "Refinement log not found. Run 'refine-backlog init' first"
  fi

  # Acquire lock
  acquire_lock "$LOCK_FILE"
  trap 'release_lock "$LOCK_FILE"' EXIT

  local repo
  repo=$(github_repo)
  local repo_root="."

  local analysis
  analysis=$(analyze_backlog "$repo" "$LOG_FILE") || fail "Failed to analyze backlog"

  # Determine stories to refine
  local stories_to_refine=""
  if [[ $refine_all -eq 1 ]]; then
    stories_to_refine=$(echo "$analysis" | jq -r '.needs_refinement[].number' | paste -sd ',' -)
  elif [[ -n "$ids_str" ]]; then
    stories_to_refine="$ids_str"
  else
    fail "Must specify --all or --ids"
  fi

  if [[ -z "$stories_to_refine" ]]; then
    log_info "No stories to refine"
    return 0
  fi

  log_info "Stories to refine: $stories_to_refine"

  # Batch stories into chunks
  local story_array=()
  IFS=',' read -ra story_array <<< "$stories_to_refine"
  local total_stories=${#story_array[@]}

  log_info "Processing $total_stories story(stories) in batches of $BATCH_SIZE..."

  local batch_index=0
  while [[ $batch_index -lt $total_stories ]]; do
    local batch_end=$((batch_index + BATCH_SIZE))
    if [[ $batch_end -gt $total_stories ]]; then
      batch_end=$total_stories
    fi

    local batch_ids=""
    for ((i=batch_index; i<batch_end; i++)); do
      if [[ -z "$batch_ids" ]]; then
        batch_ids="${story_array[$i]}"
      else
        batch_ids="$batch_ids,${story_array[$i]}"
      fi
    done

    log_info "Refining batch: $batch_ids"

    # Gather context for batch
    local context_json
    context_json=$(gather_context "$repo" "$batch_ids" "$LOG_FILE" "$repo_root") || {
      log_error "Failed to gather context for batch"
      batch_index=$((batch_end))
      continue
    }

    # Prepare Claude prompt
    local system_prompt
    system_prompt=$(cat <<'CLAUDE_SYSTEM'
You are a backlog refinement specialist. Your job is to review GitHub issues and refine them based on:
1. Current application state (what's deployed, what's been completed)
2. Architectural Decision Records (ADRs)
3. Related planning documents
4. Dependencies on other stories

For each story, identify and fix:
- Stale assumptions (compare last refinement snapshot to current app state)
- Unclear acceptance criteria
- Missing implementation details
- Dependencies that should be tracked
- Scope creep or unclear requirements

Return a JSON object with refined_stories array.
CLAUDE_SYSTEM
    )

    local user_prompt
    user_prompt="Refine these stories based on current app state and context. Return JSON with structure: {refined_stories: [{number, updated_body, key_changes, flag_for_discussion}]}\n\n$context_json"

    if [[ $dry_run -eq 1 ]]; then
      log_info "[DRY RUN] Would refine batch: $batch_ids"
    else
      # Call Claude API
      local refinement_response
      refinement_response=$(call_claude_api "$system_prompt" "$user_prompt") || {
        log_error "Failed to refine batch"
        batch_index=$((batch_end))
        continue
      }

      # Parse JSON response
      log_debug "Claude response: $refinement_response"

      # Extract refined stories and update GitHub + log
      echo "$refinement_response" | jq -c '.refined_stories[]?' 2>/dev/null | while read -r refined_story; do
        local story_num
        story_num=$(echo "$refined_story" | jq -r '.number')
        local updated_body
        updated_body=$(echo "$refined_story" | jq -r '.updated_body')

        if [[ -z "$story_num" || -z "$updated_body" ]]; then
          log_warn "Invalid refinement response for story"
          continue
        fi

        log_info "Updating GH-$story_num..."

        # Update GitHub
        github_update_issue "$repo" "$story_num" "$updated_body" || log_warn "Failed to update GH-$story_num"

        # Remove needs-refinement label
        github_remove_label "$repo" "$story_num" "needs-refinement" || true

        # Update log
        local current_app_state
        current_app_state=$(capture_app_state "$repo_root")
        update_story_refinement "$LOG_FILE" "$story_num" "$updated_body" "$current_app_state"
        log_success "Refined GH-$story_num"
      done

      # Update last_refinement timestamp
      update_log_last_refinement "$LOG_FILE"
    fi

    batch_index=$((batch_end))
  done

  log_success "Refinement complete!"
}

cmd_status() {
  local story_num=""
  local json_output=0

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --story) story_num="$2"; shift 2 ;;
      --json) json_output=1; shift ;;
      *) shift ;;
    esac
  done

  if [[ ! -f "$LOG_FILE" ]]; then
    fail "Refinement log not found. Run 'refine-backlog init' first"
  fi

  if [[ -n "$story_num" ]]; then
    # Single story status
    local story
    story=$(story_by_number "$LOG_FILE" "$story_num") || fail "Story not found: $story_num"

    if [[ $json_output -eq 1 ]]; then
      echo "$story"
    else
      echo "Story: GH-$story_num"
      echo "Title: $(echo "$story" | jq -r '.title')"
      echo "Status: $(echo "$story" | jq -r '.refinement_status')"
      echo "Last refined: $(echo "$story" | jq -r '.last_refined // "never"')"
    fi
  else
    # All stories status
    local log
    log=$(load_log "$LOG_FILE")

    if [[ $json_output -eq 1 ]]; then
      echo "$log" | jq '.stories'
    else
      local needs
      needs=$(echo "$log" | jq '[.stories[] | select(.refinement_status == "needs-refinement")] | length')
      local ready
      ready=$(echo "$log" | jq '[.stories[] | select(.refinement_status == "dev-ready")] | length')
      local new
      new=$(echo "$log" | jq '[.stories[] | select(.refinement_status == "new")] | length')

      echo "=== Refinement Status ==="
      echo "Needs refinement: $needs"
      echo "Dev-ready: $ready"
      echo "New: $new"
    fi
  fi
}

cmd_update_log() {
  if [[ ! -f "$LOG_FILE" ]]; then
    fail "Refinement log not found. Run 'refine-backlog init' first"
  fi

  log_info "Updating app state snapshot..."

  local app_state
  app_state=$(capture_app_state ".")
  update_app_state_in_log "$LOG_FILE" "$app_state"

  log_success "App state updated"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  # Handle global options
  if [[ $# -eq 0 ]]; then
    show_help
    exit 0
  fi

  case "${1:-}" in
    --help) show_help; exit 0 ;;
    --version) show_version; exit 0 ;;
    --debug) LOG_LEVEL="debug"; shift; main "$@"; exit 0 ;;
    init) shift; cmd_init "$@"; exit 0 ;;
    check) shift; cmd_check "$@"; exit 0 ;;
    refine) shift; cmd_refine "$@"; exit 0 ;;
    status) shift; cmd_status "$@"; exit 0 ;;
    update-log) cmd_update_log; exit 0 ;;
    *)
      log_error "Unknown command: $1"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
