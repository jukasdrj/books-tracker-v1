# GitHub Project Board - Manual Setup Required

**Task:** Task 1: Create GitHub Project Board (from docs/plans/2025-10-14-github-issues-migration.md)

**Status:** ⚠️ REQUIRES MANUAL AUTHENTICATION

## Issue Encountered

The GitHub CLI requires additional authentication scopes to create and manage GitHub Projects:
- Current scopes: `gist`, `read:org`, `repo`, `workflow`
- Required scopes: `project`, `read:project`

Interactive authentication is required to grant these scopes, which cannot be completed autonomously.

## Manual Steps Required

### Step 1: Refresh GitHub CLI Authentication

```bash
gh auth refresh -h github.com -s project,read:project
```

You'll need to:
1. Copy the one-time code displayed (format: XXXX-XXXX)
2. Open the provided URL in your browser
3. Paste the code and authorize the new scopes

### Step 2: Create GitHub Project Board

After authentication is refreshed, run:

```bash
gh project create \
  --owner $(gh repo view --json owner -q .owner.login) \
  --title "BooksTracker Development" \
  --format json
```

Expected output: JSON with project ID and URL

### Step 3: Get Project Number

```bash
gh project list --owner $(gh repo view --json owner -q .owner.login) --format json | jq '.projects[] | select(.title == "BooksTracker Development") | .number'
```

Save this number (e.g., `1`, `2`, etc.)

### Step 4: Update .github/project-config.sh

Edit `.github/project-config.sh` and update line 3:

```bash
export PROJECT_NUMBER=1  # Replace with actual number from Step 3
```

### Step 5: Add Custom Views (Manual via GitHub Web UI)

**Note:** GitHub CLI doesn't support creating custom Project views yet.

1. Open the project URL from Step 2 output, or run:
   ```bash
   gh project view $PROJECT_NUMBER --web
   ```

2. Create 4 custom views:

   **📋 Backlog View:**
   - Name: "📋 Backlog"
   - Filter: `status:Backlog`
   - Layout: Board

   **🏗️ In Progress View:**
   - Name: "🏗️ In Progress"
   - Filter: `status:"In Progress"`
   - Layout: Board

   **✅ Done View:**
   - Name: "✅ Done"
   - Filter: `status:Done`
   - Layout: Board

   **🤔 Decisions View:**
   - Name: "🤔 Decisions"
   - Filter: `label:type/decision`
   - Layout: Table

### Step 6: Verify Project Structure

```bash
gh project view $PROJECT_NUMBER --owner $(gh repo view --json owner -q .owner.login)
```

Expected: Shows project title, views, and empty issue list

### Step 7: Commit Configuration

```bash
git add .github/project-config.sh
git commit -m "feat(github): configure project board automation"
```

## Current Status

- ✅ Created: `.github/project-config.sh` (placeholder, needs PROJECT_NUMBER update)
- ✅ Made executable: `chmod +x .github/project-config.sh`
- ⚠️ Pending: GitHub authentication scope refresh
- ⚠️ Pending: GitHub Project creation
- ⚠️ Pending: Custom views setup (manual web UI)
- ⚠️ Pending: Final commit with actual PROJECT_NUMBER

## Files Created

1. `.github/project-config.sh` - Project configuration script (with placeholder PROJECT_NUMBER=1)
2. `.github/MANUAL_SETUP_REQUIRED.md` - This file

## Next Steps

1. Complete manual authentication (Step 1)
2. Run Steps 2-4 to create project and update config
3. Complete Step 5 via GitHub web UI to create custom views
4. Run Step 6 to verify
5. Run Step 7 to commit
6. Delete this file (`MANUAL_SETUP_REQUIRED.md`) after successful setup
7. Proceed to Task 2: Create Issue Labels

## Verification Checklist

After completing manual steps:

- [ ] GitHub CLI has `project` and `read:project` scopes
- [ ] GitHub Project "BooksTracker Development" created
- [ ] PROJECT_NUMBER obtained and updated in `.github/project-config.sh`
- [ ] 4 custom views created (Backlog, In Progress, Done, Decisions)
- [ ] `gh project view $PROJECT_NUMBER` shows project details
- [ ] Configuration committed to git
- [ ] This MANUAL_SETUP_REQUIRED.md file deleted

## References

- Plan: `docs/plans/2025-10-14-github-issues-migration.md`, Task 1
- GitHub CLI Projects Docs: https://cli.github.com/manual/gh_project
- Authentication: https://cli.github.com/manual/gh_auth_refresh
