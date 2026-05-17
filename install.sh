#!/usr/bin/env bash
# Installs the AI-authorship pre-commit hook into a git project.
#
# Usage:
#   ./install.sh                  # install into the current git repo
#   ./install.sh /path/to/repo    # install into a specific repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-$(pwd)}"

if ! git -C "$TARGET" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: '$TARGET' is not inside a git repository." >&2
    exit 1
fi

REPO_ROOT=$(git -C "$TARGET" rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"
CLAUDE_DIR="$REPO_ROOT/.claude"

# ── Install pre-commit hook ───────────────────────────────────────────────────
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"
echo "✓ pre-commit hook installed → $HOOKS_DIR/pre-commit"

# ── Install the Claude Stop capture script ────────────────────────────────────
mkdir -p "$CLAUDE_DIR/scripts"
cp "$SCRIPT_DIR/scripts/capture-ai-diff.sh" "$CLAUDE_DIR/scripts/capture-ai-diff.sh"
chmod +x "$CLAUDE_DIR/scripts/capture-ai-diff.sh"
echo "✓ capture script installed  → $CLAUDE_DIR/scripts/capture-ai-diff.sh"

# ── Add .claude/ai-changes.diff to .gitignore ────────────────────────────────
GITIGNORE="$REPO_ROOT/.gitignore"
IGNORE_PATTERNS=(
    ".claude/ai-changes.diff"
    ".claude/ai-changes-*.diff.bak"
)
for pattern in "${IGNORE_PATTERNS[@]}"; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
        echo "$pattern" >> "$GITIGNORE"
        echo "✓ added to .gitignore       → $pattern"
    fi
done

# ── Register the Stop hook in Claude Code settings ────────────────────────────
SETTINGS_FILE="$REPO_ROOT/.claude/settings.json"
mkdir -p "$CLAUDE_DIR"

CAPTURE_CMD="bash $CLAUDE_DIR/scripts/capture-ai-diff.sh"

if [ ! -f "$SETTINGS_FILE" ]; then
    cat > "$SETTINGS_FILE" <<EOF
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$CAPTURE_CMD"
          }
        ]
      }
    ]
  }
}
EOF
    echo "✓ created .claude/settings.json with Stop hook"
else
    echo ""
    echo "⚠ .claude/settings.json already exists."
    echo "  Add this entry inside the 'Stop' hooks array manually:"
    echo ""
    echo "  {\"type\":\"command\",\"command\":\"$CAPTURE_CMD\"}"
    echo ""
fi

echo ""
echo "Done! From now on:"
echo "  • Claude Code will record its diffs in .claude/ai-changes.diff after each stop"
echo "  • git commit will show an AI vs Human authorship bar"
