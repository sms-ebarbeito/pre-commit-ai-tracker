#!/usr/bin/env bash
# Runs on every Claude "Stop" event via Claude Code hooks.
# Appends the current git diff to .claude/ai-changes.diff so the
# pre-commit hook can compare it against the staged diff later.

set -euo pipefail

# Must be inside a git repo
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel)
AI_DIFF_FILE="$REPO_ROOT/.claude/ai-changes.diff"

mkdir -p "$REPO_ROOT/.claude"

DIFF=$(git diff)
STAGED=$(git diff --cached)

# Capture both unstaged and staged changes Claude may have produced
COMBINED="${DIFF}${STAGED}"

if [ -n "$COMBINED" ]; then
    {
        echo "### CLAUDE_STOP $(date -u +%Y-%m-%dT%H:%M:%SZ) ###"
        echo "$COMBINED"
    } >> "$AI_DIFF_FILE"
fi
