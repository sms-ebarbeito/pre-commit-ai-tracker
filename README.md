# AI vs Human — pre-commit authorship tracker

Tracks how much of your committed code was written by AI (Claude) vs by you.
Shows a live bar in the terminal on every `git commit`, and appends the stats permanently to the commit message.

Works **globally** — install once and every git repository on your machine gets it automatically.

---

## How it works

```
Claude writes code
      │
      ▼
Claude stops (end of turn)
      │
      ▼  [Stop hook fires]
.claude/ai-changes.diff  ◄── Claude's diff is appended here
      │
      ▼
You review, then: git commit -m "..."
      │
      ├─ pre-commit hook
      │    Compares staged diff vs .claude/ai-changes.diff
      │    Lines that match → AI
      │    Lines that don't → Human
      │    Shows colored bar in terminal
      │    Saves stats to .claude/ai-stats.tmp
      │
      ├─ prepare-commit-msg hook
      │    Appends the bar (plain text) to your commit message
      │
      └─ post-commit hook
           Archives .claude/ai-changes.diff
           Cleans up .claude/ai-stats.tmp
```

The key insight: Claude Code fires a **Stop hook** after every response. That hook captures `git diff` (modified files), `git diff --cached` (staged files), and new untracked files — so every line Claude touches is recorded before you commit.

---

## Requirements

- macOS / Linux
- Git 2.9+
- Python 3 (for Unicode block characters in the bar)
- [Claude Code](https://claude.ai/code) CLI

---

## Installation

### Global (recommended) — works for every repo on your machine

```bash
git clone <this-repo> ~/tools/pre-commit-ai-tracker
cd ~/tools/pre-commit-ai-tracker
./install-global.sh
```

What it does:
- Copies `capture-ai-diff.sh` → `~/.claude/scripts/`
- Symlinks hooks → `~/.git-hooks/` (`pre-commit`, `prepare-commit-msg`, `post-commit`)
- Sets `git config --global core.hooksPath ~/.git-hooks`
- Adds the Stop hook to `~/.claude/settings.json`

> Hooks are installed as symlinks to the cloned repo, so any update (`git pull`) takes effect immediately — no reinstall needed.

> If `~/.claude/settings.json` already exists (common if you use Claude Code), the installer will print the entry to add manually — it won't overwrite your existing config.

### Per-project

```bash
./install.sh /path/to/your/project
```

---

## Manual Stop hook setup

If you already have a `~/.claude/settings.json`, add this entry inside the `Stop` array:

```json
{
  "type": "command",
  "command": "bash /Users/YOU/.claude/scripts/capture-ai-diff.sh"
}
```

Full example:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/YOU/.claude/scripts/capture-ai-diff.sh"
          }
        ]
      }
    ]
  }
}
```

---

## What you see

### Terminal (colored)

Every `git commit` prints a bar before the commit goes through:

```
 Authorship  (120 lines)
 AI    ██████████████████████████████░░░░░░░░░░  Human
 75%                                             25%
```

### Commit message (plain text)

The stats are appended automatically to every commit message:

```
fix: validate user input on login form

─────────────────────────────────────────────
Authorship (38 lines)
AI    ██████████████████████████████░░░░░░░░░░  Human
75%                                             25%
─────────────────────────────────────────────
```

You can see it anytime with:

```bash
git log -1 --format="%B"
```

Or browse the full history:

```bash
git log --format="%s%n%b" | grep -A3 "Authorship"
```

---

## Example scenarios

### 100% AI — Claude wrote everything in this commit

```
feat: add JWT authentication middleware

─────────────────────────────────────────────
Authorship (94 lines)
AI    ████████████████████████████████████████  Human
100%                                            0%
─────────────────────────────────────────────
```

### 100% Human — you wrote it all

```
chore: update .gitignore

─────────────────────────────────────────────
Authorship (3 lines)
AI    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Human
0%                                              100%
─────────────────────────────────────────────
```

### Mixed — Claude scaffolded, you adapted

```
feat: user profile page

─────────────────────────────────────────────
Authorship (61 lines)
AI    ███████████████████████░░░░░░░░░░░░░░░░░  Human
57%                                             43%
─────────────────────────────────────────────
```

---

## Files

```
.
├── install-global.sh              # Global installer (recommended)
├── install.sh                     # Per-project installer
├── scripts/
│   └── capture-ai-diff.sh         # Claude Stop hook — records AI diffs
└── hooks/
    ├── pre-commit                  # Computes stats, shows terminal bar
    ├── prepare-commit-msg          # Appends stats to commit message
    └── post-commit                 # Archives diff, cleans up temp files
```

After installation, the capture script is copied and the hooks are symlinked:

```
~/.claude/scripts/capture-ai-diff.sh        # copy
~/.git-hooks/pre-commit          -> <repo>/hooks/pre-commit
~/.git-hooks/prepare-commit-msg  -> <repo>/hooks/prepare-commit-msg
~/.git-hooks/post-commit         -> <repo>/hooks/post-commit
```

Per-repo tracking files (git-ignored automatically):

```
<repo>/.claude/ai-changes.diff          # Active session — Claude's diffs
<repo>/.claude/ai-changes-<ts>.diff.bak # Archived after each commit
<repo>/.claude/ai-stats.tmp             # Temp file between hooks (deleted post-commit)
```

---

## Caveats

- **Accuracy is heuristic.** Lines are matched by content. If you write the same line Claude wrote, it counts as AI. If you modify a line Claude wrote, it counts as Human (which is correct).
- **Only tracks Claude Code.** The Stop hook is a Claude Code feature. Other AI tools (Copilot, Cursor, etc.) are not captured.
- **New repos start at 0%.** The tracking file doesn't exist until Claude writes something in that repo after installation.
- **`git commit` inside Claude's turn shows 0% AI.** If Claude runs `git commit` itself (not you), the Stop hook fires after the commit — too late to track. Always commit yourself.

---

## Uninstall

```bash
git config --global --unset core.hooksPath
rm -rf ~/.git-hooks
rm ~/.claude/scripts/capture-ai-diff.sh
```

Then remove the Stop hook entry from `~/.claude/settings.json`.

---

## License

MIT
