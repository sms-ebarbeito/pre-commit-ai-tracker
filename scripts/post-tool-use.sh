#!/usr/bin/env bash
# PostToolUse hook — records which lines Claude wrote, per file, per session.
# Fires after every Edit, Write, or MultiEdit tool call.
# Saves checkpoints to .git/ai/working/<session-hash>.json

set -euo pipefail

INPUT=$(cat)

python3 - "$INPUT" <<'PYEOF'
import sys, json, os, subprocess, re, hashlib

raw = sys.argv[1]
try:
    event = json.loads(raw)
except Exception:
    sys.exit(0)

tool_name = event.get("tool_name", "")
if tool_name not in ("Edit", "Write", "MultiEdit"):
    sys.exit(0)

session_id = event.get("session_id", "")
file_path = event.get("tool_input", {}).get("file_path", "")

if not session_id or not file_path or not os.path.isfile(file_path):
    sys.exit(0)

# Locate git repo
try:
    repo_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True
    ).stdout.strip()
except subprocess.CalledProcessError:
    sys.exit(0)

# Session hash per spec: SHA-256("claude-code:{session_id}"), first 16 hex chars
session_hash = hashlib.sha256(f"claude-code:{session_id}".encode()).hexdigest()[:16]

working_dir = os.path.join(repo_root, ".git", "ai", "working")
os.makedirs(working_dir, exist_ok=True)
session_file = os.path.join(working_dir, f"{session_hash}.json")

rel_path = os.path.relpath(file_path, repo_root)

# Get AI-authored line ranges via git diff.
# We diff the current file state vs HEAD (cumulative changes so far).
# For untracked files, diff against /dev/null to get all lines.
is_tracked = subprocess.run(
    ["git", "ls-files", "--error-unmatch", "--", file_path],
    capture_output=True
).returncode == 0

if is_tracked:
    diff_out = subprocess.run(
        ["git", "diff", "HEAD", "--unified=0", "--", file_path],
        capture_output=True, text=True
    ).stdout
else:
    diff_out = subprocess.run(
        ["git", "diff", "--no-index", "--unified=0", "/dev/null", file_path],
        capture_output=True, text=True
    ).stdout

# Parse hunk headers to extract added line ranges
ranges = []
for line in diff_out.splitlines():
    m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
    if m:
        start = int(m.group(1))
        count = int(m.group(2)) if m.group(2) is not None else 1
        if count > 0:
            end = start + count - 1
            ranges.append(f"{start}-{end}" if count > 1 else str(start))

if not ranges:
    sys.exit(0)

line_ranges = ",".join(ranges)

# Load or initialize session file
if os.path.exists(session_file):
    with open(session_file) as f:
        data = json.load(f)
else:
    data = {"session_hash": session_hash, "session_id": session_id, "files": {}}

# Always overwrite with current cumulative diff for this file
data["files"][rel_path] = line_ranges

with open(session_file, "w") as f:
    json.dump(data, f, indent=2)

PYEOF
