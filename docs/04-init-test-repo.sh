#!/bin/bash
# init-test-repo.sh
# 
# Sets up a clean GitHub repository for testing the refine-backlog system
# Creates sample issues and ADR/plan files to validate all workflows
#
# Usage: 
#   ./init-test-repo.sh --repo OWNER/REPO-NAME --token GITHUB_TOKEN [--local-path /path/to/repo]

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
REPO=""
TOKEN=""
LOCAL_PATH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --local-path)
      LOCAL_PATH="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  log_error "Missing required option: --repo OWNER/REPO-NAME"
  exit 1
fi

if [[ -z "$TOKEN" ]]; then
  log_error "Missing required option: --token GITHUB_TOKEN"
  exit 1
fi

# Default local path
if [[ -z "$LOCAL_PATH" ]]; then
  LOCAL_PATH="/tmp/refine-backlog-test-$(date +%s)"
fi

log_info "Setting up test repository at: $LOCAL_PATH"
log_info "GitHub repo: $REPO"

# Create directory structure
mkdir -p "$LOCAL_PATH"
cd "$LOCAL_PATH"

# Initialize git repo
log_info "Initializing git repository..."
git init
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "https://github.com/${REPO}.git"

# Create basic repo structure
log_info "Creating repo structure..."
mkdir -p docs/adr
mkdir -p planning

# Create README
cat > README.md << 'EOF'
# Backlog Refinement Test Repository

This is a test repository for validating the `refine-backlog` system.

It contains sample issues and documentation to test all workflows:
- Issue detection (label, age, dependencies)
- Refinement logic
- GitHub updates
- Log management

## Sample Issues

See GitHub Issues for details.

## Documentation

- `docs/adr/` - Architecture Decision Records
- `planning/` - Feature planning documents
EOF

# Create sample ADRs
cat > docs/adr/ADR-001.md << 'EOF'
# ADR-001: Authentication Architecture

## Status
Accepted

## Context
The system needs to authenticate users. We must choose between OAuth, JWT, or session-based auth.

## Decision
We will implement OAuth 2.0 with JWT tokens for API access.

## Consequences
- OAuth provider dependency (Google/GitHub)
- Need secure token storage on client
- Improved user experience with existing account federation
EOF

cat > docs/adr/ADR-002.md << 'EOF'
# ADR-002: Database Schema Versioning

## Status
Accepted

## Context
Database changes must be tracked and rolled back safely in production.

## Decision
Use timestamp-based migrations with rollback capability.

## Consequences
- Migrations must be idempotent
- Every migration needs a corresponding rollback
- CI/CD must validate rollback process
EOF

cat > docs/adr/ADR-003.md << 'EOF'
# ADR-003: API Rate Limiting

## Status
Pending

## Context
API needs rate limiting to prevent abuse and ensure fair resource usage.

## Decision
TBD - evaluate sliding window vs token bucket approach

## Consequences
TBD
EOF

# Create sample plan documents
cat > planning/auth-plan.md << 'EOF'
# Authentication Feature Plan

## Overview
Implement OAuth 2.0 authentication with JWT token support.

## Phases
1. OAuth provider integration (Google/GitHub)
2. JWT token generation and validation
3. Session management
4. Token refresh mechanism
5. Legacy auth migration

## Dependencies
- ADR-001: Authentication Architecture
- Database migration for auth tokens (GH-4)

## Timeline
- Phase 1-2: Sprint 1-2
- Phase 3-4: Sprint 3
- Phase 5: Sprint 4-5
EOF

cat > planning/dashboard-plan.md << 'EOF'
# Dashboard Redesign Plan

## Overview
Modernize the user dashboard with improved UX and performance.

## Components
- Header with user profile
- Main content area with widgets
- Sidebar navigation
- Settings panel

## Technical Approach
- React for UI
- Redux for state management
- Server-side rendering for performance

## Timeline
- Design: 1 week
- Implementation: 2-3 weeks
- Testing/QA: 1 week
EOF

# Create package.json for version detection
cat > package.json << 'EOF'
{
  "name": "refine-backlog-test",
  "version": "1.0.0",
  "description": "Test repository for refine-backlog system",
  "main": "index.js",
  "scripts": {
    "test": "echo 'Running tests...'"
  }
}
EOF

# Create .gitignore
cat > .gitignore << 'EOF'
node_modules/
.env
.env.local
refinement-log.json.lock
.local/refine-backlog.conf
EOF

# Commit initial repo state
log_info "Committing initial repository..."
git add .
git commit -m "Initial repo setup" || true

# Create sample issues via GitHub API
log_info "Creating sample issues..."

create_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"
  
  local data="{
    \"title\": \"$title\",
    \"body\": \"$body\",
    \"labels\": [$labels]
  }"
  
  curl -s -X POST \
    -H "Authorization: token ${TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO}/issues" \
    -d "$data" > /dev/null
}

# Issue 1: Needs refinement label
create_issue \
  "GH-1: User Authentication Overhaul" \
  "## Problem
Users need a secure way to authenticate with the system.

## Solution
Implement OAuth 2.0 with JWT tokens.

## Acceptance Criteria
1. Users can authenticate via Google or GitHub OAuth
2. JWT tokens are generated and returned on successful auth
3. Token refresh endpoint is available
4. All auth endpoints return proper error responses

## Dependencies
- ADR-001: Authentication Architecture
- Database schema for auth tokens must be ready

## Notes
See \`planning/auth-plan.md\` for full feature plan." \
  '"needs-refinement"'

# Issue 2: Open for 4+ weeks
create_issue \
  "GH-2: Dashboard Redesign" \
  "## Problem
Current dashboard is outdated and doesn't reflect modern UX patterns.

## Solution
Redesign dashboard with improved layout and performance.

## Acceptance Criteria
1. New responsive layout works on mobile/desktop
2. Loading time improved by 30%
3. All existing widgets still function
4. User preferences preserved during migration

## Technical Approach
- React components
- Redux state management
- Server-side rendering

See \`planning/dashboard-plan.md\` for details." \
  '""'

# Issue 3: Blocked by GH-4
create_issue \
  "GH-3: Implement Token Refresh Endpoint" \
  "## Problem
JWT tokens expire and users need a way to refresh them without re-authenticating.

## Solution
Implement refresh token endpoint.

## Acceptance Criteria
1. Refresh endpoint accepts old token
2. Returns new valid JWT token
3. Refresh tokens are stored securely
4. Old refresh tokens are invalidated after use

## Dependencies
This story depends on GH-4 (database schema must be ready first)." \
  '""'

# Issue 4: Blocks GH-3, setup for merging
create_issue \
  "GH-4: Database Schema for Auth Tokens" \
  "## Problem
Need database tables to store JWT and refresh tokens securely.

## Solution
Create auth_tokens and refresh_tokens tables with proper indexes.

## Acceptance Criteria
1. Tables created with migrations
2. Rollback migration tested
3. Proper indexes on user_id and token fields
4. Can handle 10k tokens per user

## Notes
This story blocks GH-3. After this merges, GH-3 becomes immediately actionable." \
  '""'

# Issue 5: Recently refined
create_issue \
  "GH-5: API Error Response Standards" \
  "## Problem
API error responses are inconsistent across endpoints.

## Solution
Define standard error response format and implement across all endpoints.

## Acceptance Criteria
1. All errors follow standard format: {error: string, code: number, details: object}
2. Error codes documented
3. All endpoints tested for consistency

## Status
Recently refined and ready for implementation." \
  '"dev-ready"'

# Issue 6: New, not yet evaluated
create_issue \
  "GH-6: Add Audit Logging" \
  "## Problem
Need to track user actions for security and compliance.

## Solution
Implement audit log for authentication and data access events.

## Acceptance Criteria
1. All auth events logged (success, failure, token refresh)
2. Logs stored with timestamps and user context
3. Logs retained for 90 days

## Notes
New story, not yet refined." \
  '""'

log_info "${GREEN}Successfully created 6 sample issues${NC}"

# Now push to GitHub
log_info "Pushing to GitHub..."
git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null || true

# Display results
echo ""
echo "=========================================="
echo "Test Repository Setup Complete"
echo "=========================================="
echo ""
echo "Repository: $REPO"
echo "Local path: $LOCAL_PATH"
echo ""
echo "Sample issues created:"
echo "  GH-1: Needs refinement (label)"
echo "  GH-2: Open 4+ weeks"
echo "  GH-3: Blocked by GH-4"
echo "  GH-4: Blocks GH-3 (for merging)"
echo "  GH-5: Recently refined (dev-ready)"
echo "  GH-6: New story"
echo ""
echo "Documentation created:"
echo "  docs/adr/ADR-001.md (auth architecture)"
echo "  docs/adr/ADR-002.md (database versioning)"
echo "  docs/adr/ADR-003.md (api rate limiting)"
echo "  planning/auth-plan.md"
echo "  planning/dashboard-plan.md"
echo ""
echo "Next steps:"
echo "  1. cd $LOCAL_PATH"
echo "  2. Initialize refine-backlog: ./refine-backlog.sh init --repo $REPO --token \$GITHUB_TOKEN"
echo "  3. Check backlog: ./refine-backlog.sh check --details"
echo "  4. Refine stories: ./refine-backlog.sh refine --all --dry-run"
echo ""
echo "For manual GitHub updates (to test dependency scenarios):"
echo "  - Go to GH-4 and mark it as 'merged' (close it)"
echo "  - Check if GH-3 is flagged for re-refinement"
echo ""
echo "=========================================="
