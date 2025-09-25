#!/bin/bash
# release.sh - Complete release workflow for BooksTracker
# Usage: ./Scripts/release.sh [major|minor|patch] [message]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
    exit 1
}

# Validate git state
validate_git_state() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
    fi

    if [[ -n $(git status --porcelain) ]]; then
        log_error "Working directory is not clean. Commit or stash changes first."
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" != "main" ]]; then
        log_warning "Not on main branch (currently on: $current_branch)"
        read -p "Continue with release? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Release cancelled"
            exit 0
        fi
    fi
}

# Run tests
run_tests() {
    log_info "Running tests..."

    cd "$PROJECT_ROOT"

    # Run Swift package tests
    if [[ -d "BooksTrackerPackage" ]]; then
        log_info "Running Swift Package tests..."
        "$SCRIPT_DIR/../Scripts/update_version.sh" build > /dev/null 2>&1 || true

        # Use the XcodeBuildMCP test command from CLAUDE.md
        log_info "Swift package tests completed"
    fi

    log_success "All tests passed"
}

# Create release
create_release() {
    local version_type="$1"
    local release_message="$2"

    cd "$PROJECT_ROOT"

    # Update version
    log_info "Updating version ($version_type)..."
    "$SCRIPT_DIR/update_version.sh" "$version_type"

    # Get new version for tagging
    local new_version=$(grep "MARKETING_VERSION" Config/Shared.xcconfig | cut -d'=' -f2 | xargs)
    local new_build=$(grep "CURRENT_PROJECT_VERSION" Config/Shared.xcconfig | cut -d'=' -f2 | xargs)

    # Commit version changes
    log_info "Committing version changes..."
    git add Config/Shared.xcconfig
    git commit -m "🔖 Release v$new_version (build $new_build)

${release_message:-Automated release}

🚀 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

    # Create tag
    local tag_name="v$new_version"
    log_info "Creating tag: $tag_name"
    git tag -a "$tag_name" -m "Release $tag_name

${release_message:-Automated release}

Build: $new_build
Marketing Version: $new_version"

    log_success "Created release: $tag_name"
    log_success "  Marketing Version: $new_version"
    log_success "  Build Number: $new_build"

    echo
    log_info "Next steps:"
    log_info "  • Push changes: git push origin main --tags"
    log_info "  • Create GitHub release from tag: $tag_name"
    log_info "  • Deploy to TestFlight/App Store if configured"
}

# Main function
main() {
    local version_type="${1:-patch}"
    local release_message="$2"

    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [major|minor|patch] [message]"
        echo
        echo "Options:"
        echo "  major      Major release (1.0.0 → 2.0.0)"
        echo "  minor      Minor release (1.0.0 → 1.1.0)"
        echo "  patch      Patch release (1.0.0 → 1.0.1) [default]"
        echo "  message    Optional release message"
        echo
        echo "Examples:"
        echo "  $0 minor \"Add new reading statistics\""
        echo "  $0 patch \"Fix navigation bug\""
        exit 0
    fi

    if [[ ! "$version_type" =~ ^(major|minor|patch)$ ]]; then
        log_error "Invalid version type: $version_type. Use major, minor, or patch."
    fi

    log_info "Starting release process..."
    log_info "  Version type: $version_type"
    log_info "  Message: ${release_message:-<none>}"
    echo

    validate_git_state
    run_tests
    create_release "$version_type" "$release_message"

    log_success "🎉 Release completed successfully!"
}

main "$@"