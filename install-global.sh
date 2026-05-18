#!/usr/bin/env bash
# Installs the AI authorship tracker globally.
# After this runs, every git repo on this machine gets AI Authorship Logs via Git Notes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_SCRIPTS="$HOME/.claude/scripts"
GIT_HOOKS="$HOME/.git-hooks"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
LOCAL_BIN="$HOME/.local/bin"

# ── 1. Scripts ────────────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_SCRIPTS"
cp "$SCRIPT_DIR/scripts/post-tool-use.sh" "$CLAUDE_SCRIPTS/post-tool-use.sh"
chmod +x "$CLAUDE_SCRIPTS/post-tool-use.sh"
echo "✓ post-tool-use     → $CLAUDE_SCRIPTS/post-tool-use.sh"

cp "$SCRIPT_DIR/scripts/build-authorship.py" "$CLAUDE_SCRIPTS/build-authorship.py"
chmod +x "$CLAUDE_SCRIPTS/build-authorship.py"
echo "✓ build-authorship  → $CLAUDE_SCRIPTS/build-authorship.py"

# ── 2. git-ai-show command ────────────────────────────────────────────────────
mkdir -p "$LOCAL_BIN"
cp "$SCRIPT_DIR/scripts/git-ai-show" "$LOCAL_BIN/git-ai-show"
chmod +x "$LOCAL_BIN/git-ai-show"
echo "✓ git-ai-show       → $LOCAL_BIN/git-ai-show"

if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    echo "  ⚠  Add $LOCAL_BIN to your PATH to use git-ai-show from anywhere"
fi

# ── 3. Global git hooks (symlinks so edits in the repo take effect immediately)
mkdir -p "$GIT_HOOKS"
for hook in pre-commit post-commit prepare-commit-msg; do
    ln -sf "$SCRIPT_DIR/hooks/$hook" "$GIT_HOOKS/$hook"
    chmod +x "$SCRIPT_DIR/hooks/$hook"
    echo "✓ $hook → $GIT_HOOKS/$hook"
done
git config --global core.hooksPath "$GIT_HOOKS"
echo "✓ git config        core.hooksPath = $GIT_HOOKS"

# ── 4. Claude Code PostToolUse hook ──────────────────────────────────────────
POST_TOOL_CMD="bash $CLAUDE_SCRIPTS/post-tool-use.sh"

if [ ! -f "$GLOBAL_SETTINGS" ]; then
    cat > "$GLOBAL_SETTINGS" <<EOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$POST_TOOL_CMD"
          }
        ]
      }
    ]
  }
}
EOF
    echo "✓ created $GLOBAL_SETTINGS with PostToolUse hook"
else
    # Check if our hook is already present
    if grep -q "post-tool-use.sh" "$GLOBAL_SETTINGS" 2>/dev/null; then
        echo "✓ PostToolUse hook already present in $GLOBAL_SETTINGS"
    else
        echo ""
        echo "⚠  $GLOBAL_SETTINGS already exists — add this PostToolUse hook manually:"
        echo ""
        echo '  "PostToolUse": ['
        echo '    {'
        echo '      "matcher": "Edit|Write|MultiEdit",'
        echo '      "hooks": [{"type": "command", "command": "'"$POST_TOOL_CMD"'"}]'
        echo '    }'
        echo '  ]'
        echo ""
        echo "  Also remove any old capture-ai-diff.sh references."
        echo ""
    fi
fi

echo ""
echo "Done. Every git repo now gets AI Authorship Logs on commit."
echo ""
echo "Usage:"
echo "  git-ai-show           → show AI authorship for HEAD"
echo "  git-ai-show <sha>     → show AI authorship for a specific commit"
echo "  git-ai-show --log     → list last 10 commits with AI line counts"
echo "  git notes --ref=refs/notes/ai show HEAD  → raw note"
