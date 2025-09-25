#!/bin/bash
# update_version.sh - Automated versioning for BooksTracker
# Usage: ./Scripts/update_version.sh [major|minor|patch|build|auto]

set -e

CONFIG_FILE="Config/Shared.xcconfig"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
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

# Get current versions
get_current_marketing_version() {
    grep "MARKETING_VERSION" "$CONFIG_FILE" | cut -d'=' -f2 | xargs
}

get_current_build_version() {
    grep "CURRENT_PROJECT_VERSION" "$CONFIG_FILE" | cut -d'=' -f2 | xargs
}

# Update marketing version
update_marketing_version() {
    local new_version="$1"
    local temp_file=$(mktemp)

    sed "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version/" "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"

    log_success "Updated marketing version to: $new_version"
}

# Update build version
update_build_version() {
    local new_build="$1"
    local temp_file=$(mktemp)

    sed "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $new_build/" "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"

    log_success "Updated build version to: $new_build"
}

# Increment semantic version
increment_version() {
    local version="$1"
    local increment_type="$2"

    IFS='.' read -ra VERSION_PARTS <<< "$version"
    local major="${VERSION_PARTS[0]}"
    local minor="${VERSION_PARTS[1]:-0}"
    local patch="${VERSION_PARTS[2]:-0}"

    case "$increment_type" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
        *)
            log_error "Invalid increment type: $increment_type"
            ;;
    esac

    echo "$major.$minor.$patch"
}

# Generate git-based build number
generate_git_build_number() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        # Use commit count as build number
        git rev-list HEAD --count
    else
        # Fallback to timestamp-based if not in git repo
        date +%s
    fi
}

# Get git tag version
get_git_tag_version() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        # Get latest tag that matches semantic versioning pattern
        git tag -l | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | sed 's/^v//'
    else
        echo ""
    fi
}

# Main logic
main() {
    cd "$PROJECT_ROOT"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
    fi

    local current_marketing=$(get_current_marketing_version)
    local current_build=$(get_current_build_version)

    log_info "Current versions:"
    log_info "  Marketing: $current_marketing"
    log_info "  Build: $current_build"
    echo

    local action="${1:-auto}"

    case "$action" in
        "major"|"minor"|"patch")
            local new_version=$(increment_version "$current_marketing" "$action")
            local new_build=$(generate_git_build_number)

            log_info "Updating to $action version..."
            update_marketing_version "$new_version"
            update_build_version "$new_build"

            log_success "Version updated:"
            log_success "  Marketing: $current_marketing → $new_version"
            log_success "  Build: $current_build → $new_build"
            ;;

        "build")
            local new_build=$(generate_git_build_number)
            update_build_version "$new_build"

            log_success "Build number updated:"
            log_success "  Build: $current_build → $new_build"
            ;;

        "auto")
            # Auto mode: check for git tags and update accordingly
            local git_version=$(get_git_tag_version)
            local new_build=$(generate_git_build_number)

            if [[ -n "$git_version" && "$git_version" != "$current_marketing" ]]; then
                log_info "Found git tag version: $git_version"
                update_marketing_version "$git_version"
                update_build_version "$new_build"

                log_success "Auto-updated versions:"
                log_success "  Marketing: $current_marketing → $git_version"
                log_success "  Build: $current_build → $new_build"
            else
                # Just update build number
                update_build_version "$new_build"
                log_success "Auto-updated build number: $current_build → $new_build"
            fi
            ;;

        "--help"|"-h")
            echo "Usage: $0 [major|minor|patch|build|auto]"
            echo
            echo "Options:"
            echo "  major    Increment major version (1.0.0 → 2.0.0)"
            echo "  minor    Increment minor version (1.0.0 → 1.1.0)"
            echo "  patch    Increment patch version (1.0.0 → 1.0.1)"
            echo "  build    Update build number only"
            echo "  auto     Auto-detect from git tags and update (default)"
            echo "  -h       Show this help"
            exit 0
            ;;

        *)
            log_error "Invalid option: $action. Use --help for usage info."
            ;;
    esac

    # Show final state
    echo
    log_info "Final versions:"
    log_info "  Marketing: $(get_current_marketing_version)"
    log_info "  Build: $(get_current_build_version)"
}

main "$@"