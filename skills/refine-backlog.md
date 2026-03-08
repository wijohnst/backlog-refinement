# Refine Backlog

Orchestrate GitHub issue refinement at scale: bash for data, Claude for judgment.

## Quick Start

This skill refines GitHub issues using:
1. **Bash** — deterministic I/O (fetch issues, gather context, apply changes)
2. **Claude** — inference (detect stale assumptions, refine requirements)

## What To Do Right Now

Parse the command line arguments the user provided. The user may have passed:
- `--all` — refine all stories needing work
- `--ids GH-123,GH-124` — refine specific stories
- `--dry-run` — preview without applying
- `status` — show refinement status
- (empty) — show backlog status and ask what to do

### If user said `status`:

Run this bash command:
```bash
refine-backlog status
```

Show the output and explain what it means.

### If user said nothing or `--all` or `--ids`:

**Step 1: Check what needs refinement**

Run:
```bash
refine-backlog check --json
```

Parse the JSON response. Extract story numbers from `.needs_refinement[]` array.

If user provided `--ids`, use those instead.

If neither `--all` nor `--ids` and check shows 0 stories needing refinement, tell the user and stop.

**Step 2: Gather context for the batch**

Prepare a comma-separated list of story IDs (e.g., "1,2,3").

Run:
```bash
refine-backlog gather-context --ids <ids>
```

This returns JSON with stories + context. Keep this for refinement.

**Step 3: Refine stories (Claude inference)**

Read the gathered context. For each story:
1. Compare `last_refinement_snapshot` to `current_app_state`
2. Identify what changed (version deployed? stories completed? new ADRs?)
3. Update the story body to reflect current reality
4. List changes in `key_changes` array
5. Flag scope issues if needed

Return JSON matching this schema:
```json
{
  "refined_stories": [
    {
      "number": 123,
      "refinement_summary": "one-line summary",
      "updated_body": "updated markdown body",
      "key_changes": ["change1", "change2"],
      "dependencies_to_update": [],
      "flag_for_discussion": false,
      "flag_details": ""
    }
  ],
  "refinement_notes": "high-level summary"
}
```

**Step 4: Apply results (if not --dry-run)**

If user passed `--dry-run`, show what would be refined and stop.

Otherwise:
- Write refined stories JSON to `/tmp/refine-result-$$.json`
- Run: `refine-backlog apply-refinement /tmp/refine-result-$$.json`
- Show output

**Step 5: Report**

Summarize:
- How many stories refined
- Key changes and patterns
- Any flagged for discussion
- Next steps

---

## Refinement Guidelines

### Detecting Stale Assumptions

Compare snapshots. Look for:

**Version changes:**
```
Last: deployed_version: "1.2.1"
Now:  deployed_version: "1.2.3"

→ Story assumed feature from v1.2.1, check if v1.2.3 deployment changes anything
```

**Completed stories:**
```
Last: completed_stories: ["GH-95"]
Now:  completed_stories: ["GH-95", "GH-101", "GH-102"]

→ Story blocked by GH-101? If GH-101 is now done, dependencies may have shifted
```

**New ADRs:**
```
Last: recent_adrs: ["ADR-003.md"]
Now:  recent_adrs: ["ADR-003.md", "ADR-005.md"]

→ Read ADR-005, check if it affects this story's approach
```

### Acceptance Criteria

Make them:
- **Specific**: "returns 401 when token expired" not "works correctly"
- **Testable**: Can be verified by QA or tests
- **Complete**: Happy path + error cases + edge cases

### When to Flag for Discussion

Set `flag_for_discussion: true` if:
- Story mixes multiple concerns (API + UI)
- Acceptance criteria missing entirely
- Scope seems too big (>3 days)
- Dependencies unclear or circular

### Preserve Structure

Keep existing headings/sections. Only restructure if it significantly improves clarity.

---

## Key Changes Examples

Good examples of what to put in `key_changes`:

- "Stale assumption: story assumed OAuth v1, but v2 deployed in v1.2.3"
- "Previously blocked by GH-101; now that it's complete, dependencies resolved"
- "ADR-005 now specifies new error handling requirements; incorporated"
- "Clarified AC: specific HTTP status codes required (401, 403, 500)"
- "Identified missing acceptance criteria for network error cases"

---

## Example Workflow

**User runs:** `/refine-backlog --ids 1`

1. You gather context for GH-1
2. You read the context and current/last snapshots
3. You refine the story, detecting stale assumptions
4. You return refined JSON
5. Script applies changes to GitHub
6. You report: "GH-1 refined: updated for v1.2.3 deployment, clarified AC"

---

## Important Notes

- Bash is available via the Bash tool; use it to run `refine-backlog` commands
- Write temp files to `/tmp/refine-result-$$.json` (use the shell's `$$` for uniqueness)
- Parse JSON responses carefully; use `jq` in bash for extraction
- Be conservative: if unsure about scope changes, flag for discussion instead
- Refinement should improve clarity and correctness, not rewrite authorship

