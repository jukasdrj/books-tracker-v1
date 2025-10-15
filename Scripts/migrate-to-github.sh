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
