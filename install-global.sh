#!/usr/bin/env bash
# Installs the AI-authorship tracker globally.
# After this runs, every git repo on this machine gets the bar automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_SCRIPTS="$HOME/.claude/scripts"
GIT_HOOKS="$HOME/.git-hooks"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

# ── 1. Capture script ─────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_SCRIPTS"
cp "$SCRIPT_DIR/scripts/capture-ai-diff.sh" "$CLAUDE_SCRIPTS/capture-ai-diff.sh"
chmod +x "$CLAUDE_SCRIPTS/capture-ai-diff.sh"
echo "✓ capture script  → $CLAUDE_SCRIPTS/capture-ai-diff.sh"

# ── 2. Global git pre-commit hook ─────────────────────────────────────────────
mkdir -p "$GIT_HOOKS"
cp "$SCRIPT_DIR/hooks/pre-commit" "$GIT_HOOKS/pre-commit"
chmod +x "$GIT_HOOKS/pre-commit"
git config --global core.hooksPath "$GIT_HOOKS"
echo "✓ pre-commit hook → $GIT_HOOKS/pre-commit"
echo "✓ git config        core.hooksPath = $GIT_HOOKS"

# ── 3. Claude Code global Stop hook ──────────────────────────────────────────
CAPTURE_CMD="bash $CLAUDE_SCRIPTS/capture-ai-diff.sh"

if [ ! -f "$GLOBAL_SETTINGS" ]; then
    cat > "$GLOBAL_SETTINGS" <<EOF
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
    echo "✓ created $GLOBAL_SETTINGS with Stop hook"
else
    echo ""
    echo "⚠  $GLOBAL_SETTINGS already exists — add this entry to your Stop hooks array:"
    echo ""
    echo "   {\"type\":\"command\",\"command\":\"$CAPTURE_CMD\"}"
    echo ""
fi

echo ""
echo "Done. Every git repo on this machine now gets the AI vs Human bar on commit."
echo "No per-project setup needed."
