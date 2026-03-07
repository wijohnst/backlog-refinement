# Backlog Refinement System - Test Suite

Comprehensive test suite for the backlog refinement system using **bats** (Bash Automated Testing System).

## Installation

### Prerequisites

- bash 4.0+
- jq (JSON processor)
- bats test framework

### Install bats

```bash
npm install --save-dev bats
# or
brew install bats-core
# or
git clone https://github.com/bats-core/bats-core.git
cd bats-core && ./install.sh /usr/local
```

## Running Tests

### Run all tests

```bash
./test/run_tests.sh
```

### Run specific test file

```bash
bats test/lib/common.bats
bats test/integration/init.bats
```

### Run tests matching a pattern

```bash
bats test/lib/common.bats -f "json"
```

### Run with verbose output

```bash
bats test/lib/common.bats -v
```

## Test Structure

### Unit Tests (lib/)

Test individual library modules in isolation using mocks:

- **common.bats** — Logging, config, JSON helpers, file I/O, locking
  - 23 tests covering all common.sh functions
  - Tests env var handling, file operations, date conversions

- **log-management.bats** — refinement-log.json operations
  - 19 tests for log CRUD, story management, app state updates
  - Tests atomic writes, JSON validation, filtering

- **backlog-analysis.bats** — Story refinement detection
  - 13 tests for reason detection and backlog analysis
  - Tests label detection, age detection, body change detection

- **github-api.bats** — GitHub REST API wrapper (mocked)
  - 13 tests using mock GitHub responses
  - Tests issue fetching, linking, version detection

### Integration Tests (integration/)

Test workflows and module interactions:

- **init.bats** — Initialization workflow
  - 15 tests for log creation, repo detection, persistence
  - Tests multi-story handling, atomic writes

- **check.bats** — Check/analysis workflow
  - 13 tests for analysis, story categorization, app state
  - Tests detection of old/changed stories

## Test Fixtures

Located in `test/fixtures/`:

- **sample-issue.json** — Single GitHub issue for testing
- **sample-log.json** — Initialized refinement log with sample stories

## Test Mocks

Located in `test/mocks/`:

- **mock-github-api.sh** — Mock GitHub API responses
  - Returns fixed test data instead of making real API calls
  - Speeds up tests and makes them deterministic

## Test Helpers

**test/test_helper.sh** provides utilities:

- `setup_test_env()` / `teardown_test_env()` — Temp directory management
- `init_test_git_repo()` — Create test git repo
- `copy_fixture()` — Copy test fixture files
- `load_mocks()` / `load_libs()` — Load dependencies
- `assert_valid_json()`, `assert_json_has_key()` — JSON assertions
- `json_get()` — Extract values from JSON

Used with bats `load` directive:

```bash
setup() {
  load ../test_helper
  load_libs        # Load libraries
  load_mocks       # Load mock functions
  setup_test_env   # Create temp test directory
}

teardown() {
  teardown_test_env  # Clean up
}
```

## Test Coverage

Current coverage:

| Module | Tests | Coverage |
|--------|-------|----------|
| common.sh | 23 | Logging, config, JSON, file I/O, locking |
| github-api.sh | 13 | API calls, issue CRUD, version detection |
| log-management.sh | 19 | Log CRUD, refinement updates, filtering |
| backlog-analysis.sh | 13 | Reason detection, categorization |
| app-state.sh | — | (Covered via integration tests) |
| context-gathering.sh | — | (To be added) |
| refine-backlog.sh | — | (To be added in CLI tests) |

**Total: 68 tests**

## What's Tested

### ✅ Completed

- Log initialization and persistence
- Story CRUD operations
- JSON validation and transformation
- Refinement status tracking
- Apple/GNU date compatibility
- Lock file handling
- Mock GitHub API responses
- Backlog analysis detection (labels, age, body changes)
- Init and check workflows

### 🚧 To Do

- Context gathering (ADR/plan files)
- CLI commands (refine, status, update-log)
- Error handling and edge cases
- Rate limiting and retries
- Full end-to-end workflows

## Adding New Tests

### Example: Test a new function

```bash
@test "new_function works correctly" {
  load ../test_helper
  load_common          # Load module

  local result
  result=$(new_function "arg1")

  # Assert result
  [ "$result" = "expected" ]
}
```

### Example: Test with fixtures

```bash
@test "function handles fixture data" {
  load ../test_helper
  setup_test_env
  copy_fixture "sample-log.json" "$TEST_TMPDIR"

  local content=$(cat "$TEST_TMPDIR/sample-log.json")
  # ... test logic

  teardown_test_env
}
```

### Example: Test JSON

```bash
@test "function returns valid JSON" {
  load ../test_helper
  load_libs

  local result=$(some_json_function)

  assert_valid_json "$result"
  assert_json_has_key "$result" "field_name"
  [ "$(json_get "$result" '.field_name')" = "expected" ]
}
```

## Debugging Tests

### Run single test

```bash
bats test/lib/common.bats -f "json_validate"
```

### Print output on failure

```bash
bats test/lib/common.bats -v
```

### Debug script

```bash
# Add to test:
run bash -c 'echo "$output" >&2'
```

### Check temp files

```bash
# In test:
echo "Temp dir: $TEST_TMPDIR"
ls -la "$TEST_TMPDIR"
```

## CI/CD Integration

### GitHub Actions example

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: npm install --save-dev bats
      - run: ./test/run_tests.sh
```

## Notes

- Tests use temporary directories; all cleanup is automatic
- Mocks prevent external API calls; tests run offline
- Date tests use system `date` command (cross-platform)
- JSON tests use `jq` for validation and extraction
- Each test is isolated; no state shared between tests

## Performance

- Full suite: ~5-10 seconds
- Unit tests: ~3 seconds
- Integration tests: ~2-5 seconds

## Troubleshooting

### "bats: command not found"

Install bats:
```bash
npm install --save-dev bats
# or
brew install bats-core
```

### Tests fail with "source: command not found"

Ensure you're using bash, not sh:
```bash
bash ./test/run_tests.sh
```

### Temp directory cleanup fails

The test helper cleans up automatically. If manual cleanup needed:
```bash
rm -rf /tmp/tmp.* 2>/dev/null || true
```

## Related Documentation

- [bats documentation](https://bats-core.readthedocs.io/)
- [jq manual](https://stedolan.github.io/jq/manual/)
- Project CLAUDE.md for architecture notes
- refine-backlog/README.md for usage
