# GitHub Workflow Guide - BooksTrack by oooe

**Migration Date:** October 14, 2025
**Repository:** books-tracker-v1
**Project Board:** https://github.com/users/jukasdrj/projects/2
**Maintainer:** @jukasdrj

---

## Table of Contents

1. [Overview](#overview)
2. [Issue Management](#issue-management)
3. [Project Board Usage](#project-board-usage)
4. [Branch Strategy](#branch-strategy)
5. [Commit Guidelines](#commit-guidelines)
6. [Pull Request Process](#pull-request-process)
7. [Release Workflow](#release-workflow)
8. [Labels & Organization](#labels--organization)
9. [Automation & Integrations](#automation--integrations)
10. [Best Practices](#best-practices)

---

## Overview

BooksTrack uses GitHub Issues and Projects for comprehensive task tracking, replacing the previous TODO.md approach. This guide establishes the official workflow for managing development tasks, features, and releases.

**Key Principles:**
- **Single Source of Truth:** GitHub Issues for all tasks
- **Transparency:** Public project board for progress tracking
- **Automation:** GitHub Actions for CI/CD, issue management
- **Documentation:** Markdown-first approach for all decisions

---

## Issue Management

### Creating Issues

**Issue Template Structure:**

```markdown
## Description
[Clear, concise description of the task/bug/feature]

## Context
- **Priority:** High/Medium/Low
- **Component:** SwiftUI/SwiftData/Backend/Testing/Documentation
- **Estimated Effort:** Small (1-2h) / Medium (3-8h) / Large (1-3d) / Epic (1w+)

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Tests added/updated
- [ ] Documentation updated

## Technical Notes
[Implementation details, architectural considerations, dependencies]

## Related Issues
- Relates to #XX
- Blocks #YY
- Blocked by #ZZ
```

### Issue Types

| Type | Label | Purpose | Example |
|------|-------|---------|---------|
| **Feature** | `enhancement` | New functionality | Add bookshelf scanner |
| **Bug** | `bug` | Code defects | Search crashes on empty query |
| **Documentation** | `documentation` | Docs updates | Update CLAUDE.md |
| **Refactor** | `refactor` | Code improvement | Extract theme logic |
| **Performance** | `performance` | Speed/memory optimization | Reduce search latency |
| **A11y** | `accessibility` | Accessibility improvements | WCAG AA compliance |
| **Testing** | `testing` | Test coverage | Add CSV import tests |
| **DevOps** | `devops` | Build/deploy/CI | Update Xcode 15.3 config |

### Priority Levels

- **P0 - Critical:** Blocks release, production bugs
- **P1 - High:** Core features, major bugs
- **P2 - Medium:** Nice-to-have features, minor bugs
- **P3 - Low:** Future enhancements, documentation

### Lifecycle States

1. **Backlog** → Issue created, not yet triaged
2. **Ready** → Triaged, ready for development
3. **In Progress** → Actively being worked on
4. **In Review** → PR submitted, awaiting review
5. **Done** → Merged to main, closed

---

## Project Board Usage

**Project URL:** https://github.com/users/jukasdrj/projects/2

### Board Columns

| Column | Purpose | Automation |
|--------|---------|------------|
| **Backlog** | Untriaged issues | Manual triage |
| **Ready** | Prioritized, unassigned | Auto-add on label |
| **In Progress** | Active development | Auto-add on assignment |
| **In Review** | PR submitted | Auto-add on PR link |
| **Done** | Merged/closed | Auto-close on merge |

### Custom Fields

- **Sprint:** Sprint 1, Sprint 2, etc.
- **Component:** SwiftUI, SwiftData, Backend, Testing, Docs
- **Effort:** Small, Medium, Large, Epic
- **Release Target:** v3.1.0, v3.2.0, Future

### Board Views

1. **By Priority:** P0/P1/P2/P3 grouping
2. **By Component:** Filter by technical area
3. **Sprint View:** Current sprint tasks only
4. **Release Roadmap:** Group by release target

---

## Branch Strategy

### Branch Naming Convention

```
<type>/<issue-number>-<short-description>

Examples:
feature/42-bookshelf-scanner
bugfix/87-search-keyboard-crash
docs/95-update-claude-md
refactor/103-theme-extraction
```

### Branch Types

- `feature/` - New features
- `bugfix/` - Bug fixes
- `hotfix/` - Critical production fixes
- `docs/` - Documentation only
- `refactor/` - Code improvements
- `test/` - Test additions
- `chore/` - Build/config updates

### Protected Branches

- **main** - Production-ready code, requires PR + review
- **develop** - Integration branch (if needed for complex features)

### Branch Lifecycle

```
1. Create branch from main
   git checkout -b feature/42-bookshelf-scanner

2. Develop & commit (see Commit Guidelines)
   git commit -m "feat: Add camera capture logic (#42)"

3. Push & create PR
   git push origin feature/42-bookshelf-scanner

4. Code review & merge
   Squash merge to main

5. Delete branch
   Automated via GitHub
```

---

## Commit Guidelines

### Commit Message Format

Following [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description> (#issue)

[optional body]

[optional footer]
```

### Commit Types

- **feat:** New feature
- **fix:** Bug fix
- **docs:** Documentation only
- **style:** Code formatting (no logic change)
- **refactor:** Code restructuring
- **perf:** Performance improvement
- **test:** Adding/updating tests
- **build:** Build system/dependencies
- **ci:** CI/CD configuration
- **chore:** Maintenance tasks

### Examples

```bash
# Feature with issue reference
feat(search): Add ISBN barcode scanner (#42)

# Bug fix with details
fix(swiftdata): Prevent duplicate library entries (#87)

Checks existing persistent IDs before creating new UserLibraryEntry.
Resolves race condition in CSV import flow.

# Documentation update
docs: Update GitHub workflow guide (#95)

# Refactor with scope
refactor(theme): Extract color system to ThemeStore (#103)
```

### Commit Best Practices

1. **Atomic commits:** One logical change per commit
2. **Descriptive messages:** Explain WHY, not just WHAT
3. **Issue links:** Always include `(#issue-number)`
4. **Present tense:** "Add feature" not "Added feature"
5. **Line length:** First line ≤72 chars, body ≤100 chars

---

## Pull Request Process

### PR Template

```markdown
## Changes
[Summary of what changed]

## Related Issues
Closes #42

## Type of Change
- [ ] Feature
- [ ] Bug fix
- [ ] Documentation
- [ ] Refactor
- [ ] Performance improvement

## Testing
- [ ] Unit tests added/updated
- [ ] Manual testing on simulator
- [ ] Real device testing (if UI/hardware)
- [ ] Regression testing

## Checklist
- [ ] Code follows Swift style guide
- [ ] No new warnings/errors
- [ ] CLAUDE.md updated (if architectural change)
- [ ] CHANGELOG.md updated (if user-facing)
- [ ] Screenshots attached (if UI change)

## Screenshots
[Attach before/after if applicable]

## Notes
[Additional context for reviewers]
```

### PR Workflow

1. **Create PR**
   - Link to issue: `Closes #42` in description
   - Add appropriate labels
   - Request review (if team)
   - Assign to project board

2. **Code Review**
   - Review checklist:
     - Swift 6 concurrency compliance
     - iOS 26 HIG adherence
     - No force unwrapping (use guard/if let)
     - SwiftData best practices
     - Test coverage

3. **CI Checks**
   - Build passes (simulator + device)
   - Tests pass (Swift Testing)
   - No new warnings
   - Code coverage ≥80% (target)

4. **Merge Strategy**
   - **Squash & Merge:** Default for features
   - **Rebase & Merge:** For clean linear history (optional)
   - **Merge Commit:** For epic branches (rare)

5. **Post-Merge**
   - Delete branch (automated)
   - Close linked issue (automated)
   - Move to "Done" on project board (automated)

---

## Release Workflow

### Semantic Versioning

Format: `MAJOR.MINOR.PATCH` (e.g., v3.1.2)

- **MAJOR:** Breaking changes, major features (v3.0.0 → v4.0.0)
- **MINOR:** New features, non-breaking (v3.0.0 → v3.1.0)
- **PATCH:** Bug fixes, performance (v3.0.0 → v3.0.1)

### Build Numbering

- **Internal Build:** Auto-incremented per Xcode build (45, 46, 47...)
- **Version Number:** Semantic version (3.1.0)
- **App Store:** Both version + build (3.1.0 build 47)

### Release Process

#### 1. Pre-Release Preparation

```bash
# Update version with script
./Scripts/update_version.sh minor  # 3.0.0 → 3.1.0

# Or full release script
./Scripts/release.sh minor "Bookshelf scanner feature"
```

#### 2. Testing Checklist

- [ ] All tests pass (simulator + device)
- [ ] Real device validation (iPhone + iPad)
- [ ] Dark mode testing
- [ ] All themes tested
- [ ] Accessibility audit (VoiceOver)
- [ ] Memory profiling (Instruments)
- [ ] Network edge cases (slow/offline)

#### 3. Documentation Updates

- [ ] CHANGELOG.md - Add release notes
- [ ] CLAUDE.md - Update version number
- [ ] README.md - Update screenshots/features
- [ ] App Store screenshots (if UI changed)

#### 4. Create GitHub Release

```markdown
## v3.1.0 - Bookshelf Scanner Beta

**Release Date:** October 14, 2025
**Build Number:** 46

### Features
- Bookshelf AI Camera Scanner (Beta) (#42)
- CSV import enrichment progress banner (#87)

### Improvements
- 3x faster search with parallel providers (#103)
- WCAG AA compliant text contrast (#118)

### Bug Fixes
- Fixed keyboard blocking on real devices (#95)
- Resolved SwiftData duplicate entries (#87)

### Technical
- Swift 6.1 compliance
- iOS 26 HIG updates
- Zero warnings, zero errors

**Full Changelog:** https://github.com/jukasdrj/books-tracker-v1/compare/v3.0.0...v3.1.0
```

#### 5. App Store Submission

```bash
# Validate build with MCP
/gogo

# Or manual via Xcode Organizer
# Archives → Validate → Distribute to App Store
```

#### 6. Post-Release

- [ ] Tag release in Git: `git tag v3.1.0 && git push --tags`
- [ ] Close milestone (if used)
- [ ] Announce on social media (optional)
- [ ] Monitor crash reports (Xcode Organizer)

---

## Labels & Organization

### Label Categories

#### Type Labels
- `enhancement` - New features
- `bug` - Code defects
- `documentation` - Docs updates
- `refactor` - Code improvement
- `performance` - Optimization
- `accessibility` - A11y improvements
- `testing` - Test coverage

#### Priority Labels
- `priority: critical` - P0 - Blocks release
- `priority: high` - P1 - Core features
- `priority: medium` - P2 - Nice-to-have
- `priority: low` - P3 - Future

#### Component Labels
- `component: swiftui` - UI layer
- `component: swiftdata` - Data layer
- `component: backend` - Cloudflare Workers
- `component: testing` - Test suite
- `component: ci/cd` - Build/deploy

#### Status Labels
- `status: blocked` - Waiting on dependency
- `status: needs-info` - Requires clarification
- `status: good-first-issue` - Beginner-friendly
- `status: help-wanted` - Community contribution welcome

#### Special Labels
- `breaking-change` - Requires major version bump
- `requires-testing` - Needs real device validation
- `security` - Security-related issue
- `technical-debt` - Code cleanup needed

### Label Usage Examples

```
Issue #42: Bookshelf Scanner
Labels: enhancement, priority: high, component: swiftui, requires-testing

Issue #87: Keyboard Crash
Labels: bug, priority: critical, component: swiftui

Issue #95: Update Docs
Labels: documentation, priority: medium, good-first-issue
```

---

## Automation & Integrations

### GitHub Actions Workflows

#### 1. CI Build & Test
**File:** `.github/workflows/ci.yml`

```yaml
name: CI Build & Test
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker -sdk iphonesimulator
      - name: Test
        run: swift test --package-path BooksTrackerPackage
```

#### 2. Auto-Label PRs
**File:** `.github/workflows/auto-label.yml`

Automatically labels PRs based on:
- Files changed (SwiftUI → `component: swiftui`)
- PR title keywords (`fix:` → `bug`)
- Size (lines changed → `size: small/medium/large`)

#### 3. Stale Issue Management
**File:** `.github/workflows/stale.yml`

- Mark issues stale after 60 days of inactivity
- Close stale issues after 14 additional days
- Exclude: `priority: critical`, `security`, `help-wanted`

#### 4. Release Drafter
**File:** `.github/workflows/release-drafter.yml`

Auto-generates release notes from merged PRs:
- Groups by type (Features, Bug Fixes, Documentation)
- Links to PRs and contributors
- Updates on every merge to main

### Project Board Automation

**Auto-Add to Project:**
```yaml
# .github/workflows/add-to-project.yml
- New issues → Backlog column
- Assigned issues → In Progress column
- PR created → In Review column
- PR merged → Done column (issue auto-closed)
```

**Auto-Label on Move:**
- Moved to "In Progress" → Add `status: in-progress`
- Moved to "Blocked" → Add `status: blocked`

### Issue Templates

**Location:** `.github/ISSUE_TEMPLATE/`

1. **bug_report.md** - Bug report template
2. **feature_request.md** - Feature proposal
3. **documentation.md** - Docs improvement
4. **performance.md** - Performance issue

### PR Template

**Location:** `.github/pull_request_template.md`

Pre-filled checklist for all PRs (see PR Template section above)

---

## Best Practices

### Issue Management

**DO:**
- Write clear, actionable descriptions
- Include reproduction steps for bugs
- Add acceptance criteria
- Link related issues
- Update status regularly

**DON'T:**
- Create duplicate issues (search first!)
- Use issues for questions (use Discussions)
- Leave issues orphaned (close if not needed)
- Over-assign (one person per issue)

### Branch Management

**DO:**
- Create branch from latest main
- Keep branches short-lived (<1 week)
- Sync with main frequently
- Delete after merge

**DON'T:**
- Commit directly to main
- Create long-living feature branches
- Mix unrelated changes in one branch

### Commit Hygiene

**DO:**
- Commit frequently (small, atomic changes)
- Write descriptive messages
- Reference issues
- Test before committing

**DON'T:**
- Commit WIP code to main
- Use vague messages ("fix stuff")
- Mix formatting with logic changes
- Commit secrets/credentials

### Code Review

**DO:**
- Review within 24 hours
- Be constructive and specific
- Test the changes locally
- Approve if minor issues (comment for future)

**DON'T:**
- Rubber-stamp approvals
- Nitpick formatting (use linter)
- Block on personal preferences
- Skip testing

### Release Management

**DO:**
- Test on real devices before release
- Update all documentation
- Follow semantic versioning
- Write clear release notes

**DON'T:**
- Rush releases without testing
- Skip version bumps
- Forget to tag releases
- Deploy on Fridays (no weekend support!)

---

## Migration from TODO.md

**Completed:** October 14, 2025

All tasks from `docs/archive/TODO.md` have been migrated to GitHub Issues. The old TODO system is deprecated.

**Legacy Reference:**
- See `docs/MIGRATION_RECORD.md` for historical mapping
- Issue numbers #1-#45 correspond to original TODO tasks
- All context preserved in issue descriptions

**Going Forward:**
- All new tasks → GitHub Issues
- Project board is single source of truth
- TODO.md archived, read-only

---

## Quick Reference

### Common Commands

```bash
# Create issue-linked branch
git checkout -b feature/42-scanner-feature

# Commit with issue reference
git commit -m "feat: Add camera scanner (#42)"

# Update version
./Scripts/update_version.sh patch

# Full release
./Scripts/release.sh minor "New features"

# MCP validation
/gogo
```

### Useful Links

- **Project Board:** https://github.com/users/jukasdrj/projects/2
- **Repository:** https://github.com/jukasdrj/books-tracker-v1
- **Issues:** https://github.com/jukasdrj/books-tracker-v1/issues
- **Releases:** https://github.com/jukasdrj/books-tracker-v1/releases
- **Actions:** https://github.com/jukasdrj/books-tracker-v1/actions

### Support

- **Questions:** GitHub Discussions
- **Bugs:** GitHub Issues with `bug` label
- **Features:** GitHub Issues with `enhancement` label
- **Security:** Email maintainer (do not file public issue!)

---

**Document Version:** 1.0.0
**Last Updated:** October 14, 2025
**Maintained By:** @jukasdrj
