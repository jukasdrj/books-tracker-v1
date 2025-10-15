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

  # Create issue (capture output directly - older gh versions don't support --json)
  gh issue create \
    --title "$title" \
    --body "$body" \
    --label "$label_type" \
    --label "$label_source" \
    --label "status/$state" > /dev/null 2>&1

  # Get the most recent issue URL
  local issue_url=$(gh issue list --limit 1 --state all | awk '{print $1}' | head -n 1)

  echo "✅ Created: Issue #$issue_url"
  return 0
}

echo "Phase 1: Migrating implementation plans (docs/plans/)"
echo "==========================================="

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

echo "Phase 3: Migrating archived decisions (docs/archive/)"
echo "==========================================="

ARCHIVE_MIGRATED=0
for archive_file in docs/archive/*.md; do
  if [ -f "$archive_file" ] && [[ "$archive_file" != *"serena-memories"* ]]; then
    # Extract title for issue creation
    title=$(grep -m 1 "^#" "$archive_file" | sed 's/^# //')
    body=$(cat "$archive_file")

    # Create as open first (gh issue create doesn't support --state)
    gh issue create \
      --title "$title" \
      --body "$body" \
      --label "type/decision" \
      --label "source/docs-archive" \
      --label "status/archived" > /dev/null 2>&1

    # Get the issue number
    issue_number=$(gh issue list --limit 1 --state all | awk '{print $1}' | head -n 1)

    # Immediately close it
    gh issue close "$issue_number" --comment "Archived historical decision record" > /dev/null 2>&1

    echo "✅ Archived: #$issue_number"
    ARCHIVE_MIGRATED=$((ARCHIVE_MIGRATED + 1))
  fi
done

echo ""
echo "✅ Migrated $ARCHIVE_MIGRATED archived decisions"
echo ""

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
    # Extract title and body
    title=$(grep -m 1 "^#" "$worker_file" | sed 's/^# //')
    body=$(cat "$worker_file")

    # Create issue as open first
    gh issue create \
      --title "$title" \
      --body "$body" \
      --label "type/decision" \
      --label "source/cloudflare-workers" \
      --label "status/archived" > /dev/null 2>&1

    # Get the issue number
    issue_number=$(gh issue list --limit 1 --state all | awk '{print $1}' | head -n 1)

    # Close immediately (these are completed work)
    gh issue close "$issue_number" --comment "Historical record migrated from cloudflare-workers/" > /dev/null 2>&1

    echo "✅ Archived: #$issue_number ($worker_file)"
    WORKERS_MIGRATED=$((WORKERS_MIGRATED + 1))
  fi
done

echo ""
echo "✅ Migrated $WORKERS_MIGRATED worker documentation files"
echo ""

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
