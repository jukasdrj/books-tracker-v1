# GitHub Issues & Projects Migration Implementation Plan

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Migrate all documentation from local MD files to GitHub Issues + Project board, eliminating repo clutter and improving staleness detection.

**Architecture:** Issue-First approach with single Kanban Project board. All plans, features, and decisions become trackable GitHub issues with labels and project views.

**Tech Stack:** GitHub CLI (`gh`), GitHub Projects v2, Bash scripting

---

## Task 1: Create GitHub Project Board

**Goal:** Set up the single Kanban board that will organize all migrated issues.

**Files:**
- N/A (GitHub operations only)

**Step 1: Create the Project**

```bash
gh project create \
  --owner $(gh repo view --json owner -q .owner.login) \
  --title "BooksTracker Development" \
  --format json
```

Expected output: JSON with project ID and URL

**Step 2: Get the project number**

```bash
gh project list --owner $(gh repo view --json owner -q .owner.login) --format json | jq '.projects[] | select(.title == "BooksTracker Development") | .number'
```

Save this number for later steps (e.g., `PROJECT_NUMBER=1`)

**Step 3: Add custom views to the project**

Via GitHub web UI (no CLI support yet):
1. Open the project URL from Step 1
2. Create 4 views:
   - **📋 Backlog** (filter: `status:Backlog`)
   - **🏗️ In Progress** (filter: `status:"In Progress"`)
   - **✅ Done** (filter: `status:Done`)
   - **🤔 Decisions** (filter: `label:type/decision`)

**Step 4: Verify project structure**

```bash
gh project view $PROJECT_NUMBER --owner $(gh repo view --json owner -q .owner.login)
```

Expected: Shows project title, views, and empty issue list

**Step 5: Document the project number**

Create `.github/project-config.sh`:

```bash
#!/bin/bash
# GitHub Project configuration for automation scripts
export PROJECT_NUMBER=1  # Update with actual number from Step 2
export REPO_OWNER=$(gh repo view --json owner -q .owner.login)
export REPO_NAME=$(gh repo view --json name -q .name)
```

Make it executable:

```bash
chmod +x .github/project-config.sh
```

**Step 6: Commit**

```bash
git add .github/project-config.sh
git commit -m "feat(github): configure project board automation"
```

---

## Task 2: Create Issue Labels

**Goal:** Set up semantic labels for categorizing migrated documentation.

**Files:**
- N/A (GitHub operations only)

**Step 1: Create type labels**

```bash
# Feature labels
gh label create "type/feature" --description "Feature request or roadmap item" --color "0E8A16"
gh label create "type/plan" --description "Implementation plan" --color "1D76DB"
gh label create "type/decision" --description "Architectural or technical decision record" --color "5319E7"

# Status labels
gh label create "status/backlog" --description "Not yet started" --color "D4C5F9"
gh label create "status/in-progress" --description "Currently being worked on" --color "FEF2C0"
gh label create "status/completed" --description "Work finished" --color "0E8A16"
gh label create "status/archived" --description "Historical record" --color "BFDADC"

# Priority labels
gh label create "priority/high" --description "High priority" --color "D93F0B"
gh label create "priority/medium" --description "Medium priority" --color "FBCA04"
gh label create "priority/low" --description "Low priority" --color "0E8A16"

# Source labels (for tracking migration)
gh label create "source/docs-future" --description "Migrated from docs/future/" --color "EDEDED"
gh label create "source/docs-plans" --description "Migrated from docs/plans/" --color "EDEDED"
gh label create "source/docs-archive" --description "Migrated from docs/archive/" --color "EDEDED"
gh label create "source/cloudflare-workers" --description "Migrated from cloudflare-workers/" --color "EDEDED"
```

**Step 2: Verify labels created**

```bash
gh label list --limit 50
```

Expected: All labels listed with correct colors and descriptions

**Step 3: Commit (documentation only)**

No commit needed (labels are in GitHub, not repo)

---

## Task 3: Create Migration Script - Part 1 (Plans)

**Goal:** Automate conversion of `docs/plans/*.md` → GitHub Issues.

**Files:**
- Create: `scripts/migrate-to-github.sh`

**Step 1: Create migration script skeleton**

```bash
mkdir -p scripts
cat > scripts/migrate-to-github.sh << 'EOF'
#!/bin/bash
set -e

# Load project configuration
source .github/project-config.sh

echo "🚀 Starting GitHub Issues migration..."
echo "Project: $REPO_OWNER/$REPO_NAME"
echo "Project Number: $PROJECT_NUMBER"
echo ""

# Function to create issue from markdown file
create_issue_from_md() {
  local md_file=$1
  local label_type=$2
  local label_source=$3
  local state=$4  # open or closed

  echo "📝 Processing: $md_file"

  # Extract title (first # heading) and body
  local title=$(grep -m 1 "^#" "$md_file" | sed 's/^# //')
  local body=$(cat "$md_file")

  # Create issue
  local issue_url=$(gh issue create \
    --title "$title" \
    --body "$body" \
    --label "$label_type" \
    --label "$label_source" \
    --label "status/$state" \
    --json url \
    --jq .url)

  echo "✅ Created: $issue_url"
  return 0
}

echo "Phase 1: Migrating implementation plans (docs/plans/)"
echo "==========================================="
EOF
chmod +x scripts/migrate-to-github.sh
```

**Step 2: Add plans migration logic**

Append to `scripts/migrate-to-github.sh`:

```bash
cat >> scripts/migrate-to-github.sh << 'EOF'

PLANS_MIGRATED=0
for plan_file in docs/plans/*.md; do
  if [ -f "$plan_file" ]; then
    create_issue_from_md "$plan_file" "type/plan" "source/docs-plans" "backlog"
    PLANS_MIGRATED=$((PLANS_MIGRATED + 1))
  fi
done

echo ""
echo "✅ Migrated $PLANS_MIGRATED implementation plans"
echo ""
EOF
```

**Step 3: Test with a single plan file**

```bash
# Dry run: manually test with one file
gh issue create \
  --title "TEST: Bookshelf Scanner Hybrid Architecture" \
  --body "$(cat docs/plans/2025-10-14-bookshelf-scanner-hybrid-architecture.md)" \
  --label "type/plan" \
  --label "source/docs-plans" \
  --label "status/backlog"
```

Expected: Issue created with full markdown content preserved

**Step 4: Close the test issue**

```bash
gh issue list --label "type/plan" --limit 1 --json number --jq '.[0].number' | xargs gh issue close
```

**Step 5: Commit**

```bash
git add scripts/migrate-to-github.sh
git commit -m "feat(scripts): add plans migration logic"
```

---

## Task 4: Create Migration Script - Part 2 (Future/Archive)

**Goal:** Add migration logic for future roadmap and archived decisions.

**Files:**
- Modify: `scripts/migrate-to-github.sh`

**Step 1: Add future docs migration**

Append to `scripts/migrate-to-github.sh`:

```bash
cat >> scripts/migrate-to-github.sh << 'EOF'

echo "Phase 2: Migrating future roadmap (docs/future/)"
echo "==========================================="

FUTURE_MIGRATED=0
for future_file in docs/future/*.md; do
  if [ -f "$future_file" ]; then
    create_issue_from_md "$future_file" "type/feature" "source/docs-future" "backlog"
    FUTURE_MIGRATED=$((FUTURE_MIGRATED + 1))
  fi
done

echo ""
echo "✅ Migrated $FUTURE_MIGRATED feature proposals"
echo ""
EOF
```

**Step 2: Add archive migration (as closed issues)**

Append to `scripts/migrate-to-github.sh`:

```bash
cat >> scripts/migrate-to-github.sh << 'EOF'

echo "Phase 3: Migrating archived decisions (docs/archive/)"
echo "==========================================="

ARCHIVE_MIGRATED=0
for archive_file in docs/archive/*.md; do
  if [ -f "$archive_file" ] && [ "$archive_file" != "docs/archive/serena-memories" ]; then
    # Create as open first (gh issue create doesn't support --state)
    local issue_number=$(gh issue create \
      --title "$(grep -m 1 "^#" "$archive_file" | sed 's/^# //')" \
      --body "$(cat "$archive_file")" \
      --label "type/decision" \
      --label "source/docs-archive" \
      --label "status/archived" \
      --json number \
      --jq .number)

    # Immediately close it
    gh issue close "$issue_number" --comment "Archived historical decision record"

    echo "✅ Archived: #$issue_number"
    ARCHIVE_MIGRATED=$((ARCHIVE_MIGRATED + 1))
  fi
done

echo ""
echo "✅ Migrated $ARCHIVE_MIGRATED archived decisions"
echo ""
EOF
```

**Step 3: Add cloudflare-workers docs migration**

Append to `scripts/migrate-to-github.sh`:

```bash
cat >> scripts/migrate-to-github.sh << 'EOF'

echo "Phase 4: Migrating Cloudflare Workers docs"
echo "==========================================="

# Only migrate status/planning docs, not technical reference
WORKER_DOCS=(
  "cloudflare-workers/AItodo.md"
  "cloudflare-workers/BOOKSHELF_SCANNING_EXECUTIVE_SUMMARY.md"
  "cloudflare-workers/DEPLOYMENT_SUCCESS_REPORT.md"
)

WORKERS_MIGRATED=0
for worker_file in "${WORKER_DOCS[@]}"; do
  if [ -f "$worker_file" ]; then
    create_issue_from_md "$worker_file" "type/decision" "source/cloudflare-workers" "archived"

    # Close immediately (these are completed work)
    local issue_number=$(gh issue list --label "source/cloudflare-workers" --limit 1 --json number --jq '.[0].number')
    gh issue close "$issue_number" --comment "Historical record migrated from cloudflare-workers/"

    WORKERS_MIGRATED=$((WORKERS_MIGRATED + 1))
  fi
done

echo ""
echo "✅ Migrated $WORKERS_MIGRATED worker documentation files"
echo ""
EOF
```

**Step 4: Add migration summary**

Append to `scripts/migrate-to-github.sh`:

```bash
cat >> scripts/migrate-to-github.sh << 'EOF'

echo "==========================================="
echo "🎉 Migration Complete!"
echo "==========================================="
echo "Plans migrated:    $PLANS_MIGRATED"
echo "Features migrated: $FUTURE_MIGRATED"
echo "Archives migrated: $ARCHIVE_MIGRATED"
echo "Workers migrated:  $WORKERS_MIGRATED"
echo ""
echo "Total issues created: $((PLANS_MIGRATED + FUTURE_MIGRATED + ARCHIVE_MIGRATED + WORKERS_MIGRATED))"
echo ""
echo "Next steps:"
echo "1. Review issues: gh issue list"
echo "2. Add issues to project: See Task 5"
echo "3. Delete migrated files: See Task 6"
EOF
```

**Step 5: Test full script (dry run)**

```bash
# Review what would be migrated
echo "Files to be migrated:"
echo "Plans: $(ls -1 docs/plans/*.md 2>/dev/null | wc -l)"
echo "Future: $(ls -1 docs/future/*.md 2>/dev/null | wc -l)"
echo "Archive: $(ls -1 docs/archive/*.md 2>/dev/null | wc -l)"
```

**Step 6: Commit**

```bash
git add scripts/migrate-to-github.sh
git commit -m "feat(scripts): add complete migration logic for all doc types"
```

---

## Task 5: Execute Migration

**Goal:** Run the migration script and verify all issues created correctly.

**Files:**
- N/A (GitHub operations only)

**Step 1: Review pre-migration state**

```bash
echo "Current documentation files:"
find docs -name "*.md" -not -path "*/testImages/*" | sort
echo ""
echo "Total MD files: $(find docs -name "*.md" -not -path "*/testImages/*" | wc -l)"
```

**Step 2: Run migration script**

```bash
./scripts/migrate-to-github.sh
```

Expected output:
```
🚀 Starting GitHub Issues migration...
Project: <owner>/<repo>
Project Number: 1

Phase 1: Migrating implementation plans (docs/plans/)
===========================================
📝 Processing: docs/plans/2025-10-14-bookshelf-scanner-hybrid-architecture.md
✅ Created: https://github.com/<owner>/<repo>/issues/1
✅ Migrated 1 implementation plans

Phase 2: Migrating future roadmap (docs/future/)
===========================================
📝 Processing: docs/future/BOOKSHELF_SCANNER_ROADMAP.md
✅ Created: https://github.com/<owner>/<repo>/issues/2
... (continues for all files)
```

**Step 3: Verify issues created**

```bash
gh issue list --limit 50 --json number,title,labels,state --jq '.[] | "\(.number): \(.title) [\(.state)] \(.labels | map(.name) | join(", "))"'
```

Expected: All migrated files appear as issues with correct labels

**Step 4: Manually add issues to project board**

Via GitHub web UI (CLI doesn't support Projects v2 yet):
1. Open project: `gh project view $PROJECT_NUMBER --web`
2. Click "+ Add item" in each view
3. Search for issues by label and add them:
   - Backlog: Add issues with `status/backlog`
   - Archived: Add closed issues with `status/archived`

Alternatively, use GraphQL (advanced):
```bash
# Get project ID
PROJECT_ID=$(gh api graphql -f query='
  query($owner: String!, $number: Int!) {
    user(login: $owner) {
      projectV2(number: $number) {
        id
      }
    }
  }' -f owner="$REPO_OWNER" -F number=$PROJECT_NUMBER --jq .data.user.projectV2.id)

# Add each issue (requires issue node ID)
# This is complex - recommend doing manually for small number of issues
```

**Step 5: Verify project board populated**

Open project in browser:
```bash
gh project view $PROJECT_NUMBER --web
```

Expected: All issues appear in correct columns based on status labels

**Step 6: Create migration record**

```bash
cat > docs/MIGRATION_RECORD.md << EOF
# Documentation Migration Record

**Date:** $(date +%Y-%m-%d)
**Migration Type:** Local MD files → GitHub Issues + Project

## Summary

- **Total Issues Created:** $(gh issue list --limit 1000 --json number --jq 'length')
- **Plans Migrated:** $(gh issue list --label "source/docs-plans" --json number --jq 'length')
- **Features Migrated:** $(gh issue list --label "source/docs-future" --json number --jq 'length')
- **Archives Migrated:** $(gh issue list --label "source/docs-archive" --json number --jq 'length')

## Project Board

- **URL:** $(gh project list --owner $REPO_OWNER --format json | jq -r '.projects[] | select(.title == "BooksTracker Development") | .url')
- **Views:** Backlog, In Progress, Done, Decisions

## Labels Created

$(gh label list --json name,description --jq '.[] | "- `\(.name)`: \(.description)"')

## Next Steps

- [ ] Delete migrated MD files (see Task 6)
- [ ] Update CLAUDE.md to reference GitHub Issues
- [ ] Update contributing workflow to use GitHub Issues

---

**Migration completed by:** scripts/migrate-to-github.sh
EOF
```

**Step 7: Commit migration record**

```bash
git add docs/MIGRATION_RECORD.md
git commit -m "docs: record GitHub Issues migration"
```

---

## Task 6: Delete Migrated Files

**Goal:** Remove all MD files that have been successfully migrated to GitHub.

**Files:**
- Delete: `docs/plans/*.md`
- Delete: `docs/future/*.md`
- Delete: `docs/archive/*.md` (except serena-memories)
- Delete: Selected cloudflare-workers/*.md

**Step 1: Verify all issues created successfully**

```bash
echo "Verifying migration completeness..."
echo ""
echo "Plans in repo: $(ls -1 docs/plans/*.md 2>/dev/null | wc -l)"
echo "Plans in GitHub: $(gh issue list --label "source/docs-plans" --json number --jq 'length')"
echo ""
echo "Future in repo: $(ls -1 docs/future/*.md 2>/dev/null | wc -l)"
echo "Future in GitHub: $(gh issue list --label "source/docs-future" --json number --jq 'length')"
echo ""
echo "Archive in repo: $(ls -1 docs/archive/*.md 2>/dev/null | wc -l)"
echo "Archive in GitHub: $(gh issue list --label "source/docs-archive" --json number --jq 'length')"
```

**Only proceed if counts match!**

**Step 2: Create backup before deletion**

```bash
mkdir -p /tmp/bookstrack-migration-backup-$(date +%Y%m%d)
cp -r docs/plans /tmp/bookstrack-migration-backup-$(date +%Y%m%d)/
cp -r docs/future /tmp/bookstrack-migration-backup-$(date +%Y%m%d)/
cp -r docs/archive /tmp/bookstrack-migration-backup-$(date +%Y%m%d)/

echo "✅ Backup created at: /tmp/bookstrack-migration-backup-$(date +%Y%m%d)"
```

**Step 3: Delete plans directory**

```bash
rm -rf docs/plans/
echo "✅ Deleted docs/plans/"
```

**Step 4: Delete future directory**

```bash
rm -rf docs/future/
echo "✅ Deleted docs/future/"
```

**Step 5: Delete archive directory (preserve serena-memories)**

```bash
# Delete individual files, not the directory
rm -f docs/archive/*.md
echo "✅ Deleted docs/archive/*.md (kept serena-memories/)"
```

**Step 6: Delete migrated cloudflare-workers docs**

```bash
rm -f cloudflare-workers/AItodo.md
rm -f cloudflare-workers/BOOKSHELF_SCANNING_EXECUTIVE_SUMMARY.md
rm -f cloudflare-workers/DEPLOYMENT_SUCCESS_REPORT.md
echo "✅ Deleted migrated cloudflare-workers documentation"
```

**Step 7: Update .gitignore to prevent future clutter**

Add to `.gitignore`:

```bash
cat >> .gitignore << 'EOF'

# Documentation should live in GitHub Issues, not local MD files
docs/plans/
docs/future/
docs/archive/*.md
!docs/archive/serena-memories/
cloudflare-workers/*_SUMMARY.md
cloudflare-workers/*_REPORT.md
EOF
```

**Step 8: Verify clean state**

```bash
echo "Remaining documentation files:"
find docs cloudflare-workers -name "*.md" -not -path "*/node_modules/*" -not -path "*/testImages/*" | sort
```

Expected: Only architectural/technical reference docs remain (README.md, SERVICE_BINDING_ARCHITECTURE.md, etc.)

**Step 9: Commit deletion**

```bash
git add -A
git commit -m "cleanup: migrate documentation to GitHub Issues

- Deleted docs/plans/ (migrated to type/plan issues)
- Deleted docs/future/ (migrated to type/feature issues)
- Deleted docs/archive/*.md (migrated to type/decision issues)
- Deleted select cloudflare-workers status docs
- Updated .gitignore to prevent future clutter

All migrated content available at:
$(gh project list --owner $REPO_OWNER --format json | jq -r '.projects[] | select(.title == "BooksTracker Development") | .url')
"
```

---

## Task 7: Update CLAUDE.md Documentation

**Goal:** Update development guide to reference GitHub Issues instead of local MD files.

**Files:**
- Modify: `CLAUDE.md:439-463` (Documentation Structure section)

**Step 1: Replace Documentation Structure section**

Find the section starting with `## Documentation Structure` (around line 439) and replace it with:

```markdown
## Documentation Structure

```
📁 Repository Documentation (Technical Reference Only)
├── 📄 CLAUDE.md                      ← Main development guide (this file)
├── 📄 MCP_SETUP.md                   ← XcodeBuildMCP configuration & workflows ⭐
├── 📄 README.md                      ← Quick start & project overview
├── 📄 CHANGELOG.md                   ← Version history & releases
├── 📄 APIcall.md                     ← API endpoint migration guide
├── 📄 REALDEVICE_FIXES.md            ← Real device debugging notes
├── 📄 FUTURE_ROADMAP.md              ← Aspirational features (archived)
├── 📁 docs/
│   ├── 📄 MIGRATION_RECORD.md        ← GitHub Issues migration log
│   └── 📁 archive/serena-memories/   ← Historical AI assistant context
├── 📁 .claude/commands/              ← Custom slash commands
│   ├── 📄 gogo.md                    ← App Store validation pipeline
│   ├── 📄 build.md                   ← Quick build check
│   ├── 📄 test.md                    ← Swift test suite runner
│   ├── 📄 device-deploy.md           ← Physical device deployment
│   └── 📄 sim.md                     ← Simulator launch & debug
└── 📁 cloudflare-workers/
    ├── 📄 README.md                  ← Backend architecture
    └── 📄 SERVICE_BINDING_ARCHITECTURE.md ← RPC technical docs
```

**📋 Plans, Features & Decisions → GitHub Issues**

All planning, roadmap, and decision documentation now lives in GitHub:

**GitHub Project Board:** [BooksTracker Development](https://github.com/YOUR_USERNAME/books-tracker-v1/projects/1)

**Finding Documentation:**
```bash
# View all issues
gh issue list

# View active work
gh issue list --label "status/in-progress"

# View roadmap/backlog
gh issue list --label "type/feature" --state open

# View implementation plans
gh issue list --label "type/plan"

# View historical decisions
gh issue list --label "type/decision" --state closed

# Search across all issues
gh issue list --search "bookshelf scanner"
```

**Creating New Documentation:**
```bash
# Create feature proposal
gh issue create --label "type/feature" --label "status/backlog"

# Create implementation plan
gh issue create --label "type/plan" --label "status/backlog"

# Record architectural decision
gh issue create --label "type/decision"
```

**Documentation Philosophy:**
- **CLAUDE.md**: Current development standards and patterns (kept in repo)
- **Technical Docs**: Architecture, API guides, setup instructions (kept in repo)
- **CHANGELOG.md**: Historical achievements and version notes (kept in repo)
- **GitHub Issues**: Plans, features, decisions, roadmap (migrated Oct 2025)
- **Benefits**: Better staleness detection, searchability, and organization
```

**Step 2: Add note about migration in Quick Start**

Find the **## Quick Start** section (around line 9) and add after the initial paragraph:

```markdown
**📋 Documentation Note:** As of October 2025, all implementation plans, feature proposals, and architectural decisions have been migrated to [GitHub Issues & Projects](https://github.com/YOUR_USERNAME/books-tracker-v1/projects/1). This guide focuses on development standards and codebase understanding.
```

**Step 3: Update references to docs/plans in Common Tasks section**

Find any references to `docs/plans/` (search: `docs/plans`) and replace with GitHub Issue references:

Before:
```markdown
See implementation plan in `docs/plans/2025-10-14-bookshelf-scanner.md`
```

After:
```markdown
See implementation plan in [GitHub Issue #123](https://github.com/YOUR_USERNAME/books-tracker-v1/issues/123)
```

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE.md): update to reflect GitHub Issues migration"
```

---

## Task 8: Update README.md

**Goal:** Add GitHub Issues links to project README for discoverability.

**Files:**
- Modify: `README.md`

**Step 1: Add GitHub Issues section**

Add this section after the "Features" section (or near the top):

```markdown
## 📋 Project Management

This project uses GitHub Issues & Projects for planning and tracking:

- **[📊 Project Board](https://github.com/YOUR_USERNAME/books-tracker-v1/projects/1)** - Current work, backlog, roadmap
- **[🎯 Active Issues](https://github.com/YOUR_USERNAME/books-tracker-v1/issues?q=is%3Aissue+is%3Aopen+label%3Astatus%2Fin-progress)** - What's being worked on now
- **[🚀 Feature Roadmap](https://github.com/YOUR_USERNAME/books-tracker-v1/issues?q=is%3Aissue+is%3Aopen+label%3Atype%2Ffeature)** - Planned features and enhancements
- **[📝 Implementation Plans](https://github.com/YOUR_USERNAME/books-tracker-v1/issues?q=is%3Aissue+label%3Atype%2Fplan)** - Detailed technical plans

**For Contributors:**
- Found a bug? [Create an issue](https://github.com/YOUR_USERNAME/books-tracker-v1/issues/new)
- Have a feature idea? [Propose it here](https://github.com/YOUR_USERNAME/books-tracker-v1/issues/new?labels=type%2Ffeature)
- Want to help? Check [good first issues](https://github.com/YOUR_USERNAME/books-tracker-v1/labels/good%20first%20issue)
```

**Step 2: Update documentation links**

Replace any references to `docs/` directories with GitHub Issue links.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs(README): add GitHub Issues project management section"
```

---

## Task 9: Create Workflow Documentation

**Goal:** Document the new GitHub Issues workflow for future reference.

**Files:**
- Create: `docs/GITHUB_WORKFLOW.md`

**Step 1: Create workflow guide**

```markdown
# GitHub Issues & Projects Workflow

**Last Updated:** 2025-10-14

This document describes how to use GitHub Issues and Projects for BooksTracker development.

## Overview

All planning, feature proposals, and decision records are tracked in GitHub:
- **Issues** = Individual work items (plans, features, decisions)
- **Project Board** = Kanban view of all work ([view here](https://github.com/YOUR_USERNAME/books-tracker-v1/projects/1))
- **Labels** = Categorization and filtering

---

## Creating New Work

### Feature Proposal

```bash
gh issue create \
  --title "Feature: Add reading statistics dashboard" \
  --label "type/feature" \
  --label "priority/medium" \
  --label "status/backlog" \
  --body "## Problem
Users want to visualize their reading habits.

## Proposed Solution
Create a statistics screen showing...

## Success Criteria
- [ ] Shows books read per month
- [ ] Shows genre distribution
- [ ] Exports to CSV"
```

### Implementation Plan

```bash
gh issue create \
  --title "Plan: Reading Statistics Implementation" \
  --label "type/plan" \
  --label "status/backlog" \
  --body "$(cat your-plan.md)"  # Or paste plan directly
```

### Architectural Decision

```bash
gh issue create \
  --title "Decision: Why we chose SwiftData over Core Data" \
  --label "type/decision" \
  --body "## Context
We needed persistent storage...

## Decision
Chose SwiftData because...

## Consequences
- Pros: Modern API, CloudKit sync
- Cons: iOS 17+ only"
```

---

## Finding Work

### View Active Work

```bash
gh issue list --label "status/in-progress"
```

### View Backlog

```bash
gh issue list --label "status/backlog" --label "type/feature"
```

### Search All Issues

```bash
gh issue list --search "camera scanner"
```

### View Project Board

```bash
gh project view 1 --web
```

---

## Working on Issues

### Start Work

```bash
# Move issue to "In Progress"
gh issue edit <issue-number> \
  --remove-label "status/backlog" \
  --add-label "status/in-progress"

# Create feature branch
git checkout -b feature/issue-<issue-number>-description
```

### Link Commits

Include issue number in commit messages:

```bash
git commit -m "feat: add statistics dashboard (#123)"
```

### Complete Work

```bash
# Create PR (automatically links to issue)
gh pr create --title "Closes #123: Reading statistics dashboard" --body "Implements #123"

# After merge, close issue
gh issue close 123 --comment "Completed in PR #456"
```

---

## Labels Reference

### Type Labels
- `type/feature` - Feature request or roadmap item
- `type/plan` - Implementation plan
- `type/decision` - Architectural or technical decision
- `type/bug` - Bug report
- `type/docs` - Documentation update

### Status Labels
- `status/backlog` - Not yet started
- `status/in-progress` - Currently being worked on
- `status/completed` - Work finished
- `status/archived` - Historical record

### Priority Labels
- `priority/high` - High priority
- `priority/medium` - Medium priority
- `priority/low` - Low priority

### Source Labels (Migration Only)
- `source/docs-plans` - Migrated from docs/plans/
- `source/docs-future` - Migrated from docs/future/
- `source/docs-archive` - Migrated from docs/archive/

---

## Project Board Views

The project has 4 views:

1. **📋 Backlog** - Planned work (`status:Backlog`)
2. **🏗️ In Progress** - Active work (`status:"In Progress"`)
3. **✅ Done** - Completed work (`status:Done`)
4. **🤔 Decisions** - Architectural decisions (`label:type/decision`)

---

## Maintenance

### Archive Completed Work

Closed issues automatically archive. To manually archive:

```bash
gh issue close <issue-number> --comment "Archived: completed on <date>"
```

### Clean Up Stale Issues

Every quarter, review open issues:

```bash
# Find old issues
gh issue list --state open --json number,title,createdAt \
  --jq '.[] | select(.createdAt < "2025-01-01") | "\(.number): \(.title)"'
```

### Update Labels

```bash
# Add new label
gh label create "platform/ios" --description "iOS-specific work" --color "0366D6"

# Update existing label
gh label edit "priority/high" --color "FF0000"
```

---

## Migration Notes

- **Migration Date:** October 14, 2025
- **Migration Script:** `scripts/migrate-to-github.sh`
- **Files Migrated:** docs/plans/, docs/future/, docs/archive/ (except serena-memories)
- **Total Issues Created:** See `docs/MIGRATION_RECORD.md`

For questions about the migration, see [Migration Record](MIGRATION_RECORD.md).
```

**Step 2: Commit**

```bash
git add docs/GITHUB_WORKFLOW.md
git commit -m "docs: add GitHub Issues workflow guide"
```

---

## Task 10: Final Verification & Cleanup

**Goal:** Verify migration success and clean up any remaining artifacts.

**Files:**
- N/A (verification only)

**Step 1: Verify issue count matches files migrated**

```bash
echo "📊 Migration Verification Report"
echo "================================="
echo ""
echo "GitHub Issues:"
echo "  Total open:   $(gh issue list --state open --json number --jq 'length')"
echo "  Total closed: $(gh issue list --state closed --json number --jq 'length')"
echo "  Plans:        $(gh issue list --label 'source/docs-plans' --json number --jq 'length')"
echo "  Features:     $(gh issue list --label 'source/docs-future' --json number --jq 'length')"
echo "  Decisions:    $(gh issue list --label 'source/docs-archive' --json number --jq 'length')"
echo ""
echo "Remaining MD files in repo:"
find docs cloudflare-workers -name "*.md" -not -path "*/node_modules/*" -not -path "*/testImages/*" | wc -l
echo ""
echo "Expected: Only technical reference docs (README, CLAUDE.md, etc.)"
```

**Step 2: Test GitHub CLI workflow**

```bash
# Test creating a new issue
gh issue create \
  --title "Test: Verify GitHub workflow" \
  --label "type/plan" \
  --label "status/backlog" \
  --body "Testing post-migration issue creation workflow"

# Test viewing issues
gh issue list --limit 5

# Clean up test issue
gh issue list --search "Test: Verify" --json number --jq '.[0].number' | xargs gh issue close
```

**Step 3: Verify project board links**

Open project board:
```bash
gh project view 1 --web
```

Manual verification checklist:
- [ ] All 4 views exist (Backlog, In Progress, Done, Decisions)
- [ ] Open issues appear in Backlog view
- [ ] Closed issues appear in Done/Decisions views
- [ ] Labels are visible and color-coded
- [ ] Issue descriptions preserved markdown formatting

**Step 4: Verify backup exists**

```bash
ls -lah /tmp/bookstrack-migration-backup-$(date +%Y%m%d)/
```

Expected: Backup directory with plans/, future/, archive/ subdirectories

**Step 5: Update CHANGELOG.md**

Add entry to `CHANGELOG.md`:

```markdown
## [Build 48] - 2025-10-14

### 🗂️ Major: Documentation Migration to GitHub Issues

**Migration Complete:**
- Migrated all implementation plans to GitHub Issues (`type/plan` label)
- Migrated all feature proposals to GitHub Issues (`type/feature` label)
- Migrated all archived decisions to closed GitHub Issues (`type/decision` label)
- Created GitHub Project board: [BooksTracker Development](https://github.com/YOUR_USERNAME/books-tracker-v1/projects/1)

**Benefits:**
- ✅ Staleness detection: GitHub tracks last activity automatically
- ✅ Better discoverability: Searchable, filterable issues
- ✅ Reduced repo clutter: Deleted docs/plans/, docs/future/, docs/archive/*.md
- ✅ Integrated workflow: Issues link to commits, PRs, and code

**Deleted Directories:**
- `docs/plans/` → Migrated to `type/plan` issues
- `docs/future/` → Migrated to `type/feature` issues
- `docs/archive/*.md` → Migrated to closed `type/decision` issues

**New Documentation:**
- `docs/GITHUB_WORKFLOW.md` - How to use GitHub Issues & Projects
- `docs/MIGRATION_RECORD.md` - Migration statistics and record
- Updated `.gitignore` to prevent future documentation clutter

**Technical Reference Preserved:**
- `CLAUDE.md` - Development standards (kept in repo)
- `README.md` - Project overview (kept in repo)
- `cloudflare-workers/README.md` - Backend architecture (kept in repo)
- `SERVICE_BINDING_ARCHITECTURE.md` - Technical docs (kept in repo)

**Files Changed:**
- Added: `scripts/migrate-to-github.sh` (migration automation)
- Added: `.github/project-config.sh` (project configuration)
- Updated: `CLAUDE.md` (reflect new documentation structure)
- Updated: `README.md` (add GitHub Issues links)
- Updated: `.gitignore` (prevent future MD clutter)

**Testing:**
- Verified all issues created with correct labels
- Verified project board views working
- Verified markdown formatting preserved
- Created backup at `/tmp/bookstrack-migration-backup-20251014/`

---
```

**Step 6: Final commit**

```bash
git add CHANGELOG.md
git commit -m "docs(CHANGELOG): document GitHub Issues migration (Build 48)"
```

**Step 7: Push to GitHub**

```bash
git push origin main
```

**Step 8: Celebrate! 🎉**

```bash
echo "🎉 Migration Complete!"
echo ""
echo "View your new GitHub Project Board:"
gh project view 1 --web
echo ""
echo "View all issues:"
gh issue list
echo ""
echo "Documentation workflow guide:"
echo "docs/GITHUB_WORKFLOW.md"
```

---

## Post-Migration Checklist

After completing all tasks, verify:

- [ ] GitHub Project created with 4 views (Backlog, In Progress, Done, Decisions)
- [ ] All labels created (type, status, priority, source)
- [ ] Migration script executed successfully
- [ ] All issues created with correct labels and content
- [ ] Issues added to project board
- [ ] Migrated MD files deleted from repo
- [ ] `.gitignore` updated to prevent future clutter
- [ ] `CLAUDE.md` updated with new documentation structure
- [ ] `README.md` includes GitHub Issues links
- [ ] `docs/GITHUB_WORKFLOW.md` created
- [ ] `docs/MIGRATION_RECORD.md` created
- [ ] `CHANGELOG.md` updated with migration entry
- [ ] Backup created in `/tmp/`
- [ ] All changes committed and pushed to GitHub

**Known Limitations:**
- GitHub CLI doesn't support adding issues to Projects v2 yet (manual step required)
- Closed issues don't automatically move to "Done" view (need manual drag)
- No automated way to create custom Project views (manual setup required)

**Future Enhancements:**
- GitHub Actions workflow to auto-label issues based on keywords
- Automated stale issue detection and archival
- Issue templates for feature proposals and bug reports
- Integration with GitHub Discussions for Q&A

---

## Related Skills

- **Systematic Debugging:** `${SUPERPOWERS_SKILLS_ROOT}/skills/debugging/systematic-debugging/SKILL.md`
- **Verification Before Completion:** `${SUPERPOWERS_SKILLS_ROOT}/skills/debugging/verification-before-completion/SKILL.md`
