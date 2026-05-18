#!/usr/bin/env python3
"""
Reads Claude's edit checkpoints from .git/ai/working/ and the current staged diff,
then builds a git-ai-standard v3.0.0 Authorship Log saved to .git/ai/pending.log.
Called by the pre-commit hook.
"""

import json, os, sys, subprocess, re

repo_root = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"],
    capture_output=True, text=True, check=True
).stdout.strip()

working_dir = os.path.join(repo_root, ".git", "ai", "working")
pending_log  = os.path.join(repo_root, ".git", "ai", "pending.log")

os.makedirs(os.path.join(repo_root, ".git", "ai"), exist_ok=True)

# Remove any stale pending log
if os.path.exists(pending_log):
    os.remove(pending_log)

# Load all session checkpoints
if not os.path.isdir(working_dir):
    sys.exit(0)

sessions = {}
for fname in os.listdir(working_dir):
    if not fname.endswith(".json"):
        continue
    with open(os.path.join(working_dir, fname)) as f:
        try:
            data = json.load(f)
            h = data.get("session_hash", fname.replace(".json", ""))
            sessions[h] = data
        except Exception:
            pass

if not sessions:
    sys.exit(0)


def parse_ranges(range_str):
    """Parse "1-10,15,20-30" into list of (start, end) tuples."""
    result = []
    for part in range_str.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            result.append((int(a), int(b)))
        elif part.isdigit():
            n = int(part)
            result.append((n, n))
    return result


def ranges_to_str(ranges):
    """Convert sorted list of (start, end) tuples to "1-10,15,20-30"."""
    parts = []
    for s, e in sorted(ranges):
        parts.append(f"{s}-{e}" if s != e else str(s))
    return ",".join(parts)


def merge_ranges(ranges):
    """Merge overlapping/adjacent (start, end) tuples."""
    if not ranges:
        return []
    sorted_r = sorted(ranges)
    merged = [sorted_r[0]]
    for s, e in sorted_r[1:]:
        ps, pe = merged[-1]
        if s <= pe + 1:
            merged[-1] = (ps, max(pe, e))
        else:
            merged.append((s, e))
    return merged


# Parse the staged diff: {rel_path: [(start, end), ...]}
staged_out = subprocess.run(
    ["git", "diff", "--cached", "--unified=0"],
    capture_output=True, text=True
).stdout

staged_files = {}
current_file = None
for line in staged_out.splitlines():
    if line.startswith("+++ b/"):
        current_file = line[6:]
        staged_files[current_file] = []
    elif line.startswith("@@ ") and current_file:
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if m:
            start = int(m.group(1))
            count = int(m.group(2)) if m.group(2) is not None else 1
            if count > 0:
                staged_files[current_file].append((start, start + count - 1))

# Build attestation: {rel_path: {session_hash: [(start, end)]}}
# A staged file is AI-attributed if it appears in any session's checkpoint.
# Line ranges: intersection of session ranges with staged ranges.
# If no intersection (line numbers shifted), fall back to all staged ranges.
attestation = {}

for session_hash, session_data in sessions.items():
    for rel_path, range_str in session_data.get("files", {}).items():
        if rel_path not in staged_files:
            continue
        staged_ranges = staged_files[rel_path]
        if not staged_ranges:
            continue

        session_ranges = parse_ranges(range_str)

        # Intersect session ranges with staged ranges
        matched = []
        for ss, se in staged_ranges:
            for rs, re_ in session_ranges:
                lo = max(ss, rs)
                hi = min(se, re_)
                if lo <= hi:
                    matched.append((lo, hi))

        # If no intersection, use all staged ranges for this file (conservative fallback)
        if not matched:
            matched = staged_ranges

        matched = merge_ranges(matched)

        if rel_path not in attestation:
            attestation[rel_path] = {}
        existing = attestation[rel_path].get(session_hash, [])
        attestation[rel_path][session_hash] = merge_ranges(existing + matched)

if not attestation:
    sys.exit(0)

# ── Attestation section ───────────────────────────────────────────────────────
attest_lines = []
for filepath in sorted(attestation):
    quoted = f'"{filepath}"' if (" " in filepath or "\t" in filepath) else filepath
    attest_lines.append(quoted)
    for session_hash, ranges in sorted(attestation[filepath].items()):
        attest_lines.append(f"  {session_hash} {ranges_to_str(ranges)}")

attestation_section = "\n".join(attest_lines)

# ── Metadata section ──────────────────────────────────────────────────────────
author = subprocess.run(["git", "config", "user.name"],  capture_output=True, text=True).stdout.strip()
email  = subprocess.run(["git", "config", "user.email"], capture_output=True, text=True).stdout.strip()
human_author = f"{author} <{email}>"

head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
if not head:
    head = "0" * 40

prompts = {}
for session_hash, session_data in sessions.items():
    accepted = sum(
        e - s + 1
        for filepath, session_map in attestation.items()
        if session_hash in session_map
        for s, e in session_map[session_hash]
    )
    prompts[session_hash] = {
        "agent_id": {
            "tool": "claude-code",
            "id": session_data.get("session_id", ""),
            "model": "claude-sonnet-4-6",
        },
        "human_author": human_author,
        "messages": [],
        "total_additions": accepted,
        "total_deletions": 0,
        "accepted_lines": accepted,
        "overriden_lines": 0,
    }

metadata = {
    "schema_version": "authorship/3.0.0",
    "base_commit_sha": head,
    "prompts": prompts,
}

log = attestation_section + "\n---\n" + json.dumps(metadata, indent=2)

with open(pending_log, "w") as f:
    f.write(log)

# ── Terminal summary ──────────────────────────────────────────────────────────
total_ai_lines = sum(
    e - s + 1
    for session_map in attestation.values()
    for ranges in session_map.values()
    for s, e in ranges
)
total_staged_lines = sum(e - s + 1 for ranges in staged_files.values() for s, e in ranges)
ai_pct = int(total_ai_lines * 100 / total_staged_lines) if total_staged_lines else 0
human_pct = 100 - ai_pct

print("")
print(f" AI Authorship  {ai_pct}% AI · {human_pct}% Human  ({total_staged_lines} lines staged)")
for filepath in sorted(attestation):
    ranges = merge_ranges([r for rm in attestation[filepath].values() for r in rm])
    n = sum(e - s + 1 for s, e in ranges)
    print(f"   {filepath}  [{ranges_to_str(ranges)}]  ({n} lines)")
print("")
