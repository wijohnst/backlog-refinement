#!/bin/bash
# Test runner for backlog refinement system

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Backlog Refinement System - Test Suite${NC}"
echo ""

# Check for bats
BATS_CMD="bats"
if ! command -v bats &> /dev/null; then
  # Try npm-installed bats
  if [[ -x "$REPO_DIR/node_modules/.bin/bats" ]]; then
    BATS_CMD="$REPO_DIR/node_modules/.bin/bats"
  else
    echo -e "${RED}✗ bats not found${NC}"
    echo ""
    echo "Install with: npm install --save-dev bats"
    exit 1
  fi
fi

echo -e "${GREEN}✓ bats found${NC}"
echo ""

# Run tests
test_files=(
  "test/lib/common.bats"
  "test/lib/log-management.bats"
  "test/lib/backlog-analysis.bats"
  "test/lib/github-api.bats"
  "test/integration/init.bats"
  "test/integration/check.bats"
)

total_tests=0
passed_tests=0
failed_tests=0

for test_file in "${test_files[@]}"; do
  if [[ ! -f "$REPO_DIR/$test_file" ]]; then
    echo -e "${RED}✗ Test file not found: $test_file${NC}"
    continue
  fi

  echo -e "${BLUE}Running: $test_file${NC}"
  if cd "$REPO_DIR" && "$BATS_CMD" "$test_file"; then
    passed_tests=$((passed_tests + 1))
  else
    failed_tests=$((failed_tests + 1))
  fi
  echo ""
done

# Summary
echo "=========================================="
if [[ $failed_tests -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}$failed_tests test file(s) failed${NC}"
  exit 1
fi
