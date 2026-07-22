#!/usr/bin/env bash
set -uo pipefail

diagnostics_dir="${1:-build/diagnostics}"
summary_file="$diagnostics_dir/summary.md"
mkdir -p "$diagnostics_dir"

python3 - "$diagnostics_dir" "$summary_file" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
summary = Path(sys.argv[2])
ansi = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
important = re.compile(
    r"(?i)(?:\berror:|\bfatal:|\*\*\s*build failed\s*\*\*|"
    r"test(?:ing)? failed|failed with exit code|linker command failed|"
    r"library '.+' not found|unknown attribute kind|process completed with exit code|"
    r"panic(?:ked)? at|assertion failed)"
)

logs = sorted(root.glob("*.log"))
selected: list[str] = []
for path in logs:
    text = ansi.sub("", path.read_text(encoding="utf-8", errors="replace"))
    for number, line in enumerate(text.splitlines(), start=1):
        if important.search(line):
            selected.append(f"{path.name}:{number}: {line[:700]}")

if not selected and logs:
    path = logs[-1]
    text = ansi.sub("", path.read_text(encoding="utf-8", errors="replace"))
    tail = text.splitlines()[-100:]
    selected = [f"{path.name}: {line[:700]}" for line in tail]

selected = selected[:180]
run_url = (
    f"https://github.com/{__import__('os').environ.get('GITHUB_REPOSITORY', '')}/actions/runs/"
    f"{__import__('os').environ.get('GITHUB_RUN_ID', '')}"
)
sha = __import__('os').environ.get('GITHUB_SHA', '')[:12]
lines = [
    "## Automated CI failure diagnostics",
    "",
    f"- Run: {run_url}",
    f"- Commit: `{sha}`",
    f"- Attempt: `{__import__('os').environ.get('GITHUB_RUN_ATTEMPT', '1')}`",
    "",
    "### Extracted failures",
    "",
    "```text",
]
lines.extend(selected or ["No compiler-style error line was found. Open the diagnostics artifact for the full logs."])
lines.extend(["```", ""])
summary.write_text("\n".join(lines), encoding="utf-8")
PY

cat "$summary_file"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat "$summary_file" >> "$GITHUB_STEP_SUMMARY"
fi

if ! command -v gh >/dev/null 2>&1 || [[ -z "${GH_TOKEN:-}" ]]; then
    exit 0
fi

title="Automated CI diagnostics"
issue_number="$({
    gh issue list \
        --state open \
        --search "\"$title\" in:title" \
        --json number,title \
        --jq ".[] | select(.title == \"$title\") | .number" 2>/dev/null || true
} | head -n 1)"

if [[ -n "$issue_number" ]]; then
    gh issue comment "$issue_number" --body-file "$summary_file" >/dev/null 2>&1 || true
else
    gh issue create \
        --title "$title" \
        --body-file "$summary_file" >/dev/null 2>&1 || true
fi
