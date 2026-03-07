# Backlog Refinement System — Design Summary

## What You're Getting

This is a complete design package for building a token-efficient backlog refinement system. The system solves three key problems:

1. **Token efficiency** — Bash scripts determine what needs refinement *without* calling Claude, then batch multiple stories into single Claude calls
2. **Stale assumption detection** — Snapshots of app state at refinement time, compared against current state to detect when assumptions become invalid
3. **Scalability** — Single command to analyze and refine entire backlogs

---

## The Four Documents

### 1. **01-DESIGN.md** — System Architecture
- **What it is**: High-level design of how the system works
- **Audience**: You, before implementation (to understand trade-offs and design decisions)
- **Key sections**:
  - Core problems solved
  - Data model (refinement-log.json structure)
  - System components (bash scripts, Claude skill)
  - Workflow diagrams
  - Design principles
  - Future extensions (for v2+)

**Read this first** to understand the big picture.

### 2. **02-IMPLEMENTATION-SPEC.md** — Detailed Specification
- **What it is**: Line-by-line spec for building the system
- **Audience**: Engineer implementing the system (or providing this to Claude for implementation)
- **Key sections**:
  - Bash script structure and function signatures
  - GitHub API wrapper functions
  - Backlog analysis logic
  - Context gathering (ADRs, plans, etc.)
  - Log management
  - App state capture
  - Main CLI with subcommands
  - Claude skill definition and input/output format
  - Integration and execution flow
  - Configuration and installation

**Use this as the implementation prompt.** It's detailed enough that you (or Claude) can build from it with minimal ambiguity.

### 3. **03-TEST-PLAN.md** — Testing Strategy
- **What it is**: Comprehensive test plan covering unit, integration, and manual validation
- **Audience**: QA engineer, or you testing your own implementation
- **Key sections**:
  - Unit tests by module (using bats framework)
  - Integration tests for full workflows
  - Manual validation scenarios (using test repo)
  - Test fixtures and mocks
  - CI/CD integration
  - Expected test results and coverage goals

**Use this to validate the implementation.** Covers all workflows and edge cases.

### 4. **04-init-test-repo.sh** — Test Repository Setup
- **What it is**: Bash script that creates a clean GitHub repo for testing
- **Audience**: You, before running tests
- **What it does**:
  - Creates directory structure
  - Sets up git repo with remote
  - Creates sample ADR and plan documents
  - Creates 6 sample GitHub issues (various states)
  - Pushes everything to GitHub
  - Prints next steps

**Run this to set up your test environment** before implementing or testing.

---

## How to Use This Package

### Scenario 1: You're Building This Yourself
1. Read **01-DESIGN.md** to understand the system
2. Use **02-IMPLEMENTATION-SPEC.md** as your spec/checklist
3. Use **03-TEST-PLAN.md** to validate as you build
4. Run **04-init-test-repo.sh** to set up test repo before implementation

### Scenario 2: You're Giving This to Claude (or Another Engineer)
1. Compile **01-DESIGN.md** + **02-IMPLEMENTATION-SPEC.md** into single implementation prompt
2. Include **03-TEST-PLAN.md** for validation
3. Provide **04-init-test-repo.sh** for testing

### Scenario 3: You Want to Validate the Design First
1. Read **01-DESIGN.md** thoroughly
2. Run **04-init-test-repo.sh** to create test repo
3. Manually work through "what if" scenarios to validate design choices
4. Then proceed to implementation

---

## Key Design Decisions

### 1. **Bash for Determinism**
Fetching, filtering, and log management are in bash because:
- Fast (no LLM round-trips)
- Reproducible (deterministic)
- Auditable (easy to see exactly what happened)

Claude is **only** used for the actual refinement work (comparing story to context, updating AC, etc.).

### 2. **Refinement Log as State Machine**
The `refinement-log.json` tracks:
- What was true about the app when story was last refined (snapshot)
- What's true now (current app state)
- Why the story needs refinement (label, age, dependency, etc.)

This enables:
- Detecting stale assumptions (snapshot vs current)
- Avoiding redundant refinements
- Auditability (why was this refined, when, what changed?)

### 3. **Batch Refinement via Claude**
Instead of refining stories one-at-a-time:
- Fetch all stories needing refinement
- Gather full context for all
- Send to Claude in single prompt
- Claude refines all together, returns JSON
- Bash updates GitHub from JSON

**Result**: 1 API call to Claude instead of N, saves tokens and improves coherence across stories.

### 4. **GitHub Labels as Source of Truth**
- `needs-refinement` label = story must be refined (overrides log)
- Label is user-facing (can be added manually)
- Log is system-facing (tracks history)

This keeps the source of truth visible in GitHub, not hidden in a config file.

### 5. **Minimal App State Snapshot**
Track only what matters:
- Current git SHA
- Deployed version
- Recently closed stories (last 7 days)
- Recently added ADRs (last 7 days)

Grow this list based on what you learn.

---

## Data Model at a Glance

### Refinement Log (`refinement-log.json`)
```json
{
  "version": "1.0",
  "metadata": { /* timestamps, repo name */ },
  "app_state": { /* git SHA, version, recent changes */ },
  "stories": {
    "GH-123": {
      "refinement_status": "dev-ready" | "needs-refinement" | "new",
      "refinement_reasons": [ /* why needs refinement */ ],
      "last_refined": { /* timestamp, snapshot, assumptions */ },
      "dependencies": { /* blocks, blocked_by, relates_to */ },
      "context_references": { /* which ADRs/plans used */ }
    }
  }
}
```

### Workflow Summary
```
1. bash: refine-backlog check
   → Analyze which stories need refinement (no Claude)
   
2. bash: refine-backlog refine --all
   → Gather context (ADRs, plans, related stories)
   → Build single prompt with all stories
   
3. Claude: Refine all stories
   → Compare last snapshot to current app state
   → Update AC, note stale assumptions
   → Return JSON with refined bodies
   
4. bash: Update GitHub + log
   → Remove needs-refinement label
   → Add dev-ready label
   → Update issue bodies
   → Update refinement-log.json
```

---

## Testing Approach

### Unit Tests (with bats)
- Test each bash function independently
- Mock GitHub API and Claude
- Fast, deterministic, good coverage

### Integration Tests (with bats)
- Test full workflows (init → check → refine → status)
- Test error scenarios
- Test idempotency

### Manual Validation (with test repo)
- Real GitHub repo with sample issues
- Real git history
- End-to-end workflows
- Validate GitHub updates actually work

---

## Configuration

### Installation
```bash
# One-time setup
./init-refine-backlog.sh --repo OWNER/REPO --token $GITHUB_TOKEN

# Creates:
# - refinement-log.json
# - .local/bin/refine-backlog symlink
# - .local/refine-backlog.conf (tokens, config)
```

### Usage
```bash
# Check what needs refinement
refine-backlog check --details

# Refine all stories
refine-backlog refine --all --confirm

# Check specific story status
refine-backlog status --story GH-123

# Dry-run (preview without updating)
refine-backlog refine --all --dry-run
```

---

## Next Steps

### To Build This:
1. **Start with 02-IMPLEMENTATION-SPEC.md**
   - Create bash script structure
   - Implement lib/common.sh first (utilities others depend on)
   - Implement lib/github-api.sh (GitHub interactions)
   - Implement lib/backlog-analysis.sh (detection logic)
   - ... etc in dependency order

2. **Then implement the Claude skill**
   - Use the input/output format from spec
   - Test with mock bash layer first

3. **Validate with tests**
   - Run unit tests as you build each module
   - Run integration tests for full workflows
   - Use test repo for end-to-end validation

### To Iterate:
- **Does the refinement log have the right fields?**
  Use actual refinements to refine the design
  
- **Are "needs refinement" triggers right?**
  Maybe you need to trigger on specific ADR updates, not just age
  
- **Is batch refinement efficient enough?**
  Maybe batch size needs adjustment, or some stories need refinement before others
  
- **Are Claude instructions clear?**
  Try with real stories, iterate on the skill prompt

---

## Success Criteria

When the system is working:

✅ `refine-backlog check` shows what needs refinement without LLM calls  
✅ `refine-backlog refine --all` refines multiple stories in single Claude call  
✅ GitHub issues updated with refined bodies, labels changed correctly  
✅ refinement-log.json updated with timestamps and snapshots  
✅ Re-running check shows no false positives  
✅ Adding "needs-refinement" label triggers re-refinement  
✅ Dependencies are tracked and can trigger re-refinement  
✅ All workflows tested and validated  

---

## FAQ

**Q: Can I refine stories without the app state snapshot?**  
A: Yes, the system works without snapshots. Snapshots let you detect when assumptions become stale. Start simple, add snapshots later if needed.

**Q: Do I have to use batch refinement?**  
A: No, you can refine stories one-at-a-time. Batch is just more efficient.

**Q: What if my repo doesn't have ADRs or plan docs?**  
A: The system works without them. If they're missing, Claude refines based on issue body + related stories only.

**Q: How do I handle stories that depend on each other?**  
A: GitHub issue links (blocks, blocked_by) track this. When one story is merged, its dependents can be flagged for re-refinement.

**Q: Can I use this with Jira/Linear instead of GitHub?**  
A: Not without modification. The design is GitHub-specific. Could be adapted, but would need new API layer.

**Q: What's the max batch size?**  
A: Depends on story complexity and context size. Start with 5-10 stories per batch, increase if Claude handles it well.

**Q: Is the refinement-log.json format locked?**  
A: No, it's v1.0. You can iterate as you learn what data matters.

---

## Contact / Feedback

If you:
- Build this and find gaps in the spec
- Implement and discover missing edge cases
- Test and find scenarios that don't work
- Iterate and improve the design

Please document the changes and iterate the design docs accordingly. This is a living design, not final.

---

## Document Checklist

- ✅ **01-DESIGN.md** — System architecture (you are here)
- ✅ **02-IMPLEMENTATION-SPEC.md** — Detailed specification
- ✅ **03-TEST-PLAN.md** — Testing strategy
- ✅ **04-init-test-repo.sh** — Test repo setup script

**All documents are ready for use.**

