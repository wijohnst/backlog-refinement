#!/bin/bash
# Shared utilities for backlog refinement system

set -euo pipefail

# Guard against re-sourcing
[[ -n "${_REFINE_COMMON_LOADED:-}" ]] && return 0
_REFINE_COMMON_LOADED=1

# =============================================================================
# LOGGING
# =============================================================================

# Color codes (not readonly to allow re-sourcing in tests)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*" >&2
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

log_debug() {
  if [[ "${LOG_LEVEL:-info}" == "debug" ]]; then
    echo -e "${BLUE}◆${NC} $*" >&2
  fi
}

log_success() {
  echo -e "${GREEN}✓${NC} $*" >&2
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

fail() {
  log_error "$@"
  exit 1
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" &> /dev/null; then
    fail "Required command not found: $cmd"
  fi
}

require_env() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    fail "Required environment variable not set: $var"
  fi
}

# =============================================================================
# CONFIG MANAGEMENT
# =============================================================================

github_token() {
  # Try env var first
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN"
    return 0
  fi

  # Try config file
  if [[ -f "${HOME}/.local/refine-backlog.conf" ]]; then
    if grep -q "^GITHUB_TOKEN=" "${HOME}/.local/refine-backlog.conf" 2>/dev/null; then
      grep "^GITHUB_TOKEN=" "${HOME}/.local/refine-backlog.conf" | cut -d'=' -f2 | tr -d '"'
      return 0
    fi
  fi

  fail "GitHub token not found. Set GITHUB_TOKEN env var or run: refine-backlog init"
}

anthropic_api_key() {
  # Try env var first
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "$ANTHROPIC_API_KEY"
    return 0
  fi

  # Try config file
  if [[ -f "${HOME}/.local/refine-backlog.conf" ]]; then
    if grep -q "^ANTHROPIC_API_KEY=" "${HOME}/.local/refine-backlog.conf" 2>/dev/null; then
      grep "^ANTHROPIC_API_KEY=" "${HOME}/.local/refine-backlog.conf" | cut -d'=' -f2 | tr -d '"'
      return 0
    fi
  fi

  fail "Anthropic API key not found. Set ANTHROPIC_API_KEY env var or run: refine-backlog init"
}

github_repo() {
  # Try env var first
  if [[ -n "${GITHUB_REPO:-}" ]]; then
    echo "$GITHUB_REPO"
    return 0
  fi

  # Try config file
  if [[ -f "${HOME}/.local/refine-backlog.conf" ]]; then
    if grep -q "^GITHUB_REPO=" "${HOME}/.local/refine-backlog.conf" 2>/dev/null; then
      grep "^GITHUB_REPO=" "${HOME}/.local/refine-backlog.conf" | cut -d'=' -f2 | tr -d '"'
      return 0
    fi
  fi

  # Try git remote origin
  if git rev-parse --git-dir > /dev/null 2>&1; then
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [[ -n "$remote_url" ]]; then
      # Extract owner/repo from https://github.com/owner/repo or git@github.com:owner/repo
      if [[ "$remote_url" =~ github\.com[:/]([^/]+)/(.+)\.git$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
      fi
    fi
  fi

  fail "GitHub repo not found. Set GITHUB_REPO env var or run in a git repo with origin remote"
}

log_level() {
  if [[ -n "${LOG_LEVEL:-}" ]]; then
    echo "$LOG_LEVEL"
  else
    echo "info"
  fi
}

# =============================================================================
# JSON HELPERS
# =============================================================================

json_validate() {
  local json="$1"
  echo "$json" | jq empty 2>/dev/null
}

jq_filter() {
  local json="$1"
  local filter="$2"
  echo "$json" | jq -r "$filter" 2>/dev/null || echo ""
}

json_to_var() {
  local json="$1"
  local key="$2"
  echo "$json" | jq -r ".\"$key\" // empty" 2>/dev/null || echo ""
}

# =============================================================================
# FILE UTILITIES
# =============================================================================

ensure_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    touch "$file"
  fi
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
}

file_hash() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return 1
  fi

  local hash
  if command -v shasum &> /dev/null; then
    hash=$(/usr/bin/shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1) || hash=""
  fi

  # Fall back to sha256sum if shasum failed
  if [[ -z "$hash" ]] && command -v sha256sum &> /dev/null; then
    hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1) || hash=""
  fi

  echo "$hash"
}

hash_string() {
  local string="$1"

  local hash
  if command -v shasum &> /dev/null; then
    hash=$(echo -n "$string" | /usr/bin/shasum -a 256 | cut -d' ' -f1) || hash=""
  fi

  # Fall back to sha256sum if shasum failed
  if [[ -z "$hash" ]] && command -v sha256sum &> /dev/null; then
    hash=$(echo -n "$string" | sha256sum | cut -d' ' -f1) || hash=""
  fi

  echo "$hash"
}

# =============================================================================
# LOCKING
# =============================================================================

acquire_lock() {
  local lock_file="$1"
  local timeout="${2:-30}"
  local start_time
  start_time=$(date +%s)

  while [[ -f "$lock_file" ]]; do
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [[ $elapsed -gt $timeout ]]; then
      fail "Could not acquire lock after ${timeout}s: $lock_file"
    fi

    sleep 0.5
  done

  echo "$$" > "$lock_file"
}

release_lock() {
  local lock_file="$1"
  if [[ -f "$lock_file" ]]; then
    rm -f "$lock_file"
  fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Parse ISO 8601 date to seconds since epoch (cross-platform)
iso_to_epoch() {
  local iso_date="$1"

  if command -v date &> /dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS date
      date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" "+%s" 2>/dev/null || echo "0"
    else
      # GNU date
      date -d "$iso_date" "+%s" 2>/dev/null || echo "0"
    fi
  else
    echo "0"
  fi
}

# Get current time in ISO 8601 format
current_iso_time() {
  if [[ "$(uname)" == "Darwin" ]]; then
    date -u "+%Y-%m-%dT%H:%M:%SZ"
  else
    date -u -Iseconds | sed 's/+00:00/Z/'
  fi
}

# Days since timestamp (ISO format)
days_since() {
  local iso_date="$1"
  local then_epoch
  then_epoch=$(iso_to_epoch "$iso_date")
  if [[ "$then_epoch" == "0" ]]; then
    echo "999"  # Return large number if parse failed
    return 1
  fi

  local now
  now=$(date +%s)
  local diff=$((now - then_epoch))
  local days=$((diff / 86400))
  echo "$days"
}

# =============================================================================
# EXPORT FUNCTIONS FOR SOURCING
# =============================================================================

# Make functions available when sourced
export -f log_info log_warn log_error log_debug log_success
export -f fail require_command require_env
export -f github_token anthropic_api_key github_repo log_level
export -f json_validate jq_filter json_to_var
export -f ensure_file ensure_dir file_hash hash_string
export -f acquire_lock release_lock
export -f iso_to_epoch current_iso_time days_since
