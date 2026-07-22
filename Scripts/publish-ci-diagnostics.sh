#!/usr/bin/env bash
set -euo pipefail

diagnostics_dir="${1:-build/diagnostics}"
summary_file="$diagnostics_dir/summary.md"
mkdir -p "$diagnostics_dir"

python3 - "$diagnostics_dir" "$summary_file" <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
summary = Path(sys.argv[2])
ansi = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

# Single-line compiler, linker, test, package-manager and CI failures.
important = re.compile(
    r"(?i)(?:"
    r"\berror:|\bfatal:|\bpanic(?:ked)? at|assertion failed|"
    r"\*\*\s*(?:build|test) failed\s*\*\*|test(?:ing)? failed|"
    r"failed with exit code|process completed with exit code|"
    r"linker command failed|symbol\(s\) not found|duplicate symbol|"
    r"undefined symbols? for architecture|library ['\"].+['\"] not found|"
    r"unknown attribute kind|overlapping accesses|exclusive access|"
    r"cannot find|could not find|no such module|no such file or directory|"
    r"use of unresolved module|unresolved import|type annotations needed|"
    r"does not conform to protocol|ambiguous use of|invalid redeclaration|"
    r"missing required module|module compiled with|swift compiler error|"
    r"cargo: error|make(?:\[[0-9]+\])?: \*\*\*"
    r")"
)

# Multi-line sections where the useful cause sits after the heading.
block_starts = re.compile(
    r"(?i)(?:"
    r"undefined symbols? for architecture|duplicate symbols? for architecture|"
    r"testing failed:|the following build commands failed:|"
    r"failures:\s*$|error\[E[0-9]{4}\]"
    r")"
)
block_stops = re.compile(
    r"(?i)(?:"
    r"^\s*ld: symbol\(s\) not found|^\s*clang: error: linker command failed|"
    r"^\s*\*\*\s*(?:build|test) failed\s*\*\*|"
    r"^\s*process completed with exit code"
    r")"
)


def clean_lines(path: Path) -> list[str]:
    text = ansi.sub("", path.read_text(encoding="utf-8", errors="replace"))
    return text.splitlines()


def add_range(indices: set[int], start: int, end: int, length: int) -> None:
    start = max(0, start)
    end = min(length, end)
    indices.update(range(start, end))


logs = sorted(root.glob("*.log"))
sections: list[tuple[str, list[str]]] = []

for path in logs:
    lines = clean_lines(path)
    selected_indices: set[int] = set()

    for index, line in enumerate(lines):
        if important.search(line):
            add_range(selected_indices, index - 3, index + 5, len(lines))

        if block_starts.search(line):
            # Preserve the whole first linker/compiler block, capped to keep the
            # issue body manageable. Undefined-symbol names commonly occupy
            # dozens of lines after the heading.
            end = min(len(lines), index + 120)
            for cursor in range(index + 1, end):
                if block_stops.search(lines[cursor]):
                    end = min(len(lines), cursor + 4)
                    break
            add_range(selected_indices, index - 2, end, len(lines))

    if selected_indices:
        ordered = sorted(selected_indices)
        rendered: list[str] = []
        previous = -2
        for index in ordered:
            if index > previous + 1:
                rendered.append("...")
            rendered.append(f"{index + 1}: {lines[index][:900]}")
            previous = index
        sections.append((path.name, rendered[:260]))

if not sections and logs:
    path = logs[-1]
    lines = clean_lines(path)
    tail = lines[-140:]
    start = max(1, len(lines) - len(tail) + 1)
    sections.append(
        (path.name, [f"{number}: {line[:900]}" for number, line in enumerate(tail, start=start)])
    )

run_url = (
    f"https://github.com/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/"
    f"{os.environ.get('GITHUB_RUN_ID', '')}"
)
sha = os.environ.get("GITHUB_SHA", "")[:12]
run_number = os.environ.get("GITHUB_RUN_NUMBER", "")
lines_out = [
    "## Automated CI failure diagnostics",
    "",
    f"- Run: {run_url}",
    f"- Run number: `{run_number}`",
    f"- Commit: `{sha}`",
    f"- Attempt: `{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}`",
    f"- Full logs artifact: `Seal-CI-Diagnostics-{run_number}`",
    "",
    "### Extracted failures with context",
    "",
]

if sections:
    for name, rendered in sections:
        lines_out.extend([f"#### `{name}`", "", "```text"])
        lines_out.extend(rendered)
        lines_out.extend(["```", ""])
else:
    lines_out.extend(
        [
            "```text",
            "No compiler-style error line was found. Open the diagnostics artifact for the full logs.",
            "```",
            "",
        ]
    )

summary.write_text("\n".join(lines_out), encoding="utf-8")
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
