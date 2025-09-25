#!/bin/bash
# setup_hooks.sh - Install git hooks for automated versioning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔧${NC} Setting up git hooks for automated versioning..."

cd "$PROJECT_ROOT"

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️${NC} Not in a git repository. Hooks not installed."
    exit 1
fi

# Install hooks
if [[ -f ".githooks/pre-commit" ]]; then
    echo "Installing pre-commit hook..."
    cp ".githooks/pre-commit" ".git/hooks/pre-commit"
    chmod +x ".git/hooks/pre-commit"
    echo -e "${GREEN}✅${NC} Pre-commit hook installed"
else
    echo -e "${YELLOW}⚠️${NC} Pre-commit hook source not found"
fi

echo
echo -e "${GREEN}🎉${NC} Git hooks setup complete!"
echo
echo "The following hooks are now active:"
echo "  • pre-commit: Auto-updates build numbers on each commit"
echo
echo "To disable temporarily: git commit --no-verify"