# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A self-installing Git Notes-based system that tracks which lines in a commit were authored by Claude Code vs. a human, following the [git-ai standard v3.0.0](docs/git_ai_standard_v3.0.0.md). No external services, no telemetry — everything is bash + python3 + Git Notes (`refs/notes/ai`).

There is no build, lint, or test suite. This repo *is* the tooling — changes are verified by installing it (globally or per-repo) and observing behavior across real `git commit` calls.

## Architecture / data flow

```
Claude edits a file (Edit/Write/MultiEdit)
   → PostToolUse hook: scripts/post-tool-use.sh
   → writes .git/ai/working/<session-hash>.json
        { session_hash, session_id, files: { "path": "1-10,15" } }
        line ranges = `git diff HEAD --unified=0` hunk headers (cumulative, overwritten each call)

git commit -m "..."
   → pre-commit hook (hooks/pre-commit)
        → runs scripts/build-authorship.py
            - reads all .git/ai/working/*.json checkpoints
            - intersects each session's line ranges with the staged diff
              (`git diff --cached --unified=0`)
            - writes .git/ai/pending.log  (attestation + JSON metadata, "---"-separated)
            - writes .git/ai/stats.tmp    (AI_PCT, HUMAN_PCT, bar strings)
            - prints the authorship bar to the terminal
        → chains to .git/hooks/pre-commit (project-level) if present

   → prepare-commit-msg hook (hooks/prepare-commit-msg)
        → reads .git/ai/stats.tmp, appends the authorship bar to the commit message
        → no-ops for merge/squash commits

   → post-commit hook (hooks/post-commit)
        → attaches .git/ai/pending.log as a Git Note: `git notes --ref=refs/notes/ai add -f -F ...`
        → archives .git/ai/working/*.json → .git/ai/archive/<short-sha>/
        → chains to .git/hooks/post-commit (project-level) if present
```

Inspect results with `scripts/git-ai-show` (`git-ai-show`, `git-ai-show <sha>`, `git-ai-show --log [n]`, or raw via `git notes --ref=refs/notes/ai show HEAD`).

## Two installers — know which one applies

- **`install-global.sh`** — the primary, current path. Installs scripts to `~/.claude/scripts/`, `git-ai-show` to `~/.local/bin/`, symlinks `hooks/{pre-commit,post-commit,prepare-commit-msg}` into `~/.git-hooks/`, sets `git config --global core.hooksPath ~/.git-hooks`, and registers the `PostToolUse` hook in `~/.claude/settings.json`. Hooks are symlinks, so editing files in this repo takes effect immediately for every repo on the machine (after `git pull`).
- **`install.sh`** — an older per-project installer (Stop-hook based, writes `.claude/ai-changes.diff` via `scripts/capture-ai-diff.sh`). It predates the Git Notes rewrite and is not part of the current `refs/notes/ai` flow described above; treat it as legacy unless asked to maintain it.

## Key implementation details to preserve

- **Session hash**: `SHA-256("claude-code:" + session_id)[:16]` — must match the spec's hashing rule (section 1.2.3) for hash stability across commits.
- **Line ranges captured at edit time**, not by content diffing at commit time — this is deliberate (avoids false attribution from whitespace/duplicate lines). Don't change `post-tool-use.sh` to do content-based matching.
- **Attestation/metadata format** must stay compatible with `docs/git_ai_standard_v3.0.0.md`: two sections separated by a line containing exactly `---`, attestation lines indented with exactly two spaces, `schema_version: "authorship/3.0.0"`, the `overriden_lines` (typo, per spec errata E-001) field name.
- **Working state lives under `.git/ai/`** (`working/`, `pending.log`, `stats.tmp`, `archive/<sha>/`) — never committed, always per-repo.
- All hooks `chain to project-level hooks` at `.git/hooks/<name>` after running, so installing globally must not break repos that already have their own hooks.
- `prepare-commit-msg` must early-exit on `merge`/`squash` commit sources.

## Caveats baked into the design (don't try to "fix" these)

- Only Claude Code via PostToolUse is tracked; other AI tools are not captured.
- Commits made by Claude itself via the Bash tool bypass `PostToolUse` checkpoint state for that commit's session.
- No rebase/stash/cherry-pick recalculation is implemented — notes move with `git notes` defaults only (per the spec's section 2, this is a known gap, not yet implemented here).
