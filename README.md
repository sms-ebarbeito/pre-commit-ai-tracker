# AI Authorship Tracker

Tracks which lines in your commits were written by Claude Code, stored as **Git Notes** — clean history, zero telemetry, no external services.

Inspired by the [git-ai standard v3](docs/git_ai_standard_v3.0.0.md), but implemented entirely in bash + python3 with no binaries to trust.

Works **globally** — install once and every git repository on your machine gets it automatically.

---

## How it works

```
Claude writes code (Edit / Write / MultiEdit tools)
      │
      ▼  [PostToolUse hook fires after each edit]
.git/ai/working/<session-hash>.json  ◄── line ranges recorded per file
      │
      ▼
You review, then: git commit -m "..."
      │
      ├─ pre-commit hook
      │    Reads checkpoints from .git/ai/working/
      │    Cross-references with staged diff (line numbers, not content)
      │    Prints summary to terminal
      │    Saves Authorship Log to .git/ai/pending.log
      │
      └─ post-commit hook
           Attaches pending.log as Git Note → refs/notes/ai
           Archives session checkpoints
```

Line ranges are captured **at edit time** via `git diff`, not by comparing content at commit time — this avoids false attribution caused by special characters, whitespace, or repeated lines.

---

## Requirements

- macOS / Linux
- Git 2.9+
- Python 3
- [Claude Code](https://claude.ai/code) CLI

---

## Installation

```bash
git clone <this-repo> ~/tools/ai-authorship
cd ~/tools/ai-authorship
./install-global.sh
```

What it does:
- Copies scripts → `~/.claude/scripts/`
- Copies `git-ai-show` → `~/.local/bin/`
- Symlinks hooks → `~/.git-hooks/` (`pre-commit`, `post-commit`, `prepare-commit-msg`)
- Sets `git config --global core.hooksPath ~/.git-hooks`
- Adds the `PostToolUse` hook to `~/.claude/settings.json`

> Hooks are symlinks to the cloned repo — a `git pull` updates them immediately with no reinstall.

> If `~/.claude/settings.json` already exists, the installer prints the entry to add manually.

---

## Manual settings.json entry

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/post-tool-use.sh"
          }
        ]
      }
    ]
  }
}
```

---

## What you see

### At commit time (terminal)

```
 Authorship  (234 lines)
 AI    ████████████████████████████████████░░░░  Human
 94%                                             6%
   src/auth/middleware.py  [1-180]  (180 lines)
   tests/test_auth.py      [1-54]   (54 lines)
```

### In the commit message (permanent)

```
feat: add JWT authentication middleware

─────────────────────────────────────────────
Authorship (234 lines)
AI    ████████████████████████████████████░░░░  Human
94%                                             6%
─────────────────────────────────────────────
```

### Inspecting authorship

```bash
git-ai-show              # detailed view for HEAD
git-ai-show <sha>        # specific commit
git-ai-show --log        # last 10 commits with AI line counts
git-ai-show --log 20     # last 20 commits

# raw note
git notes --ref=refs/notes/ai show HEAD
```

`git-ai-show` output:

```
 Commit  a1b2c3d4e5f6
 feat: add JWT authentication middleware
 Schema: authorship/3.0.0

 Attestation
   src/auth/middleware.py
     a1b2c3d4e5f6abcd  lines 1-180  (180 lines)
   tests/test_auth.py
     a1b2c3d4e5f6abcd  lines 1-54   (54 lines)

 Sessions
   a1b2c3d4e5f6abcd
     tool:    claude-code / claude-sonnet-4-6
     author:  Your Name <you@example.com>
     lines:   234 accepted
```

---

## Files

```
.
├── install-global.sh              # Global installer
├── install.sh                     # Per-project installer
├── docs/
│   └── git_ai_standard_v3.0.0.md # Reference spec
├── scripts/
│   ├── post-tool-use.sh           # PostToolUse hook — records line ranges
│   ├── build-authorship.py        # Builds the Authorship Log at commit time
│   └── git-ai-show                # CLI to inspect Git Notes
└── hooks/
    ├── pre-commit                  # Calls build-authorship.py, prints summary
    ├── post-commit                 # Attaches Git Note, archives checkpoints
    └── prepare-commit-msg          # Appends plain-text bar to commit message
```

After installation:

```
~/.claude/scripts/post-tool-use.sh      # copy
~/.claude/scripts/build-authorship.py   # copy
~/.local/bin/git-ai-show                # copy
~/.git-hooks/pre-commit          -> <repo>/hooks/pre-commit
~/.git-hooks/post-commit         -> <repo>/hooks/post-commit
~/.git-hooks/prepare-commit-msg  -> <repo>/hooks/prepare-commit-msg
```

Per-repo working files (inside `.git/`, never committed):

```
.git/ai/working/<session-hash>.json     # checkpoint per Claude session
.git/ai/pending.log                     # authorship log waiting to be attached
.git/ai/stats.tmp                       # bar stats passed to prepare-commit-msg
.git/ai/archive/<sha>/                  # archived checkpoints after commit
```

---

## Caveats

- **Only tracks Claude Code** via PostToolUse. Other tools (Copilot, Cursor, etc.) are not captured.
- **Bash commits are not tracked.** If Claude runs `git commit` itself via the Bash tool, the PostToolUse hook doesn't fire for that commit. Always commit yourself.
- **No rebase/stash tracking.** Line attribution is only computed for the commit it was created in — rebasing moves the note but doesn't recalculate line numbers.

---

## Format

Authorship Logs follow the [git-ai standard v3.0.0](docs/git_ai_standard_v3.0.0.md) and are stored under `refs/notes/ai`. The format is designed to be compatible with tooling built on that standard.

---

## Uninstall

```bash
git config --global --unset core.hooksPath
rm -rf ~/.git-hooks
rm ~/.claude/scripts/post-tool-use.sh ~/.claude/scripts/build-authorship.py
rm ~/.local/bin/git-ai-show
```

Remove the `PostToolUse` hook entry from `~/.claude/settings.json`.

---

## License

MIT
