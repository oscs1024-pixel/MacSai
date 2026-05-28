#!/bin/bash
# One-time setup: creates the homebrew-macclean tap repo and a workflow
# that keeps it in sync with Casks/mac-clean.rb in this repo.
#
# Requires: gh CLI authenticated
# Usage: bash scripts/setup-homebrew-tap.sh

set -euo pipefail

GH_USER=$(gh api user --jq .login)
TAP_REPO="homebrew-macclean"

echo "=== Setting up Homebrew tap for ${GH_USER}/${TAP_REPO} ==="

# Check if already exists
if gh repo view "${GH_USER}/${TAP_REPO}" &>/dev/null; then
    echo "Tap repo ${GH_USER}/${TAP_REPO} already exists."
    exit 0
fi

TMP=$(mktemp -d)
cd "$TMP"

mkdir -p Casks
cp /Users/iliya/Dev/MacClean/Casks/mac-clean.rb Casks/mac-clean.rb

cat > README.md <<EOF
# homebrew-macclean

Homebrew tap for [Mac Clean](https://github.com/${GH_USER}/MacClean) — the open-source Mac cleaner.

## Install

\`\`\`bash
brew tap ${GH_USER}/macclean
brew install --cask mac-clean
\`\`\`

This tap is automatically updated when new versions of Mac Clean are released.
EOF

git init -b main >/dev/null
git add .
git commit -m "Initial tap with Mac Clean cask" >/dev/null

gh repo create "${TAP_REPO}" --public --source . --description "Homebrew tap for Mac Clean" --push

echo ""
echo "✅ Tap created at https://github.com/${GH_USER}/${TAP_REPO}"
echo ""
echo "Users can now install with:"
echo "  brew tap ${GH_USER}/macclean"
echo "  brew install --cask mac-clean"
echo ""
echo "Next: the release workflow will keep the cask in sync via auto-commits."

cd /
rm -rf "$TMP"
